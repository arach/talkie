//
//  ClassifierPipelineBenchmark.swift
//  TalkieKit
//
//  Benchmarks NLEmbedding as a shared feature backbone for a trained
//  logistic regression head vs the hand-crafted NeedsLLMClassifier.
//  Measures wall-clock cost, accuracy against labels, and agreement.
//

import Foundation
import NaturalLanguage
import Accelerate

// MARK: - Test Case

public struct ClassifierPipelineTestCase {
    public let input: String
    public let expectedNeedsLLM: Bool
    public let difficulty: String

    public init(input: String, expectedNeedsLLM: Bool, difficulty: String) {
        self.input = input
        self.expectedNeedsLLM = expectedNeedsLLM
        self.difficulty = difficulty
    }
}

// MARK: - Result Types

public struct LatencyStats {
    public let median: Double
    public let p95: Double
    public let mean: Double
    public let min: Double
    public let max: Double

    public init(from samples: [Double]) {
        let sorted = samples.sorted()
        let n = sorted.count
        guard n > 0 else {
            self.median = 0; self.p95 = 0; self.mean = 0; self.min = 0; self.max = 0
            return
        }
        self.min = sorted[0]
        self.max = sorted[n - 1]
        self.mean = sorted.reduce(0, +) / Double(n)
        self.median = n % 2 == 0
            ? (sorted[n/2 - 1] + sorted[n/2]) / 2.0
            : sorted[n/2]
        let p95Index = Swift.min(Int(Double(n) * 0.95), n - 1)
        self.p95 = sorted[p95Index]
    }
}

public struct FanOutStats {
    public let headCount: Int
    public let embedOnce: LatencyStats
    public let allHeads: LatencyStats
    public let perHead: LatencyStats
}

public struct ClassifierPipelineBenchmarkResult {
    public let totalCases: Int
    public let wordEmbedding: LatencyStats
    public let sentenceEmbedding: LatencyStats?
    public let handCrafted: LatencyStats
    public let singleHead: LatencyStats
    public let fanOut: FanOutStats
    public let hcAccuracy: Double
    public let hcCorrect: Int
    public let trainedHeadAccuracy: Double
    public let trainedHeadCorrect: Int
    public let hcVsTrainedAgreement: Double
    public let hcVsTrainedAgree: Int
    public let trainingTimeMs: Double
    public let trainingCaseCount: Int
    public let perDifficulty: [(difficulty: String, hcAccuracy: Double, trainedAccuracy: Double, agreement: Double, count: Int)]
}

// MARK: - Logistic Regression Head

private struct LogisticRegressionHead {
    let weights: [Double]
    let bias: Double

    func predict(_ x: [Double]) -> Double {
        let dim = Swift.min(weights.count, x.count)
        var dot = 0.0
        for i in 0..<dim {
            dot += weights[i] * x[i]
        }
        let logit = dot + bias
        return 1.0 / (1.0 + exp(-logit))
    }

    func classify(_ x: [Double]) -> Bool {
        predict(x) >= 0.5
    }

    init(weights: [Double] = [], bias: Double = 0.0) {
        self.weights = weights
        self.bias = bias
    }
}

// MARK: - Benchmark Runner

@MainActor
public final class ClassifierPipelineBenchmark {
    public static let shared = ClassifierPipelineBenchmark()

    private static let headCount = 4

    private init() {}

    public func runFullBenchmark() -> ClassifierPipelineBenchmarkResult {
        run(testCases: Self.testCases)
    }

    public func run(testCases: [ClassifierPipelineTestCase]) -> ClassifierPipelineBenchmarkResult {
        let wordEmb = NLEmbedding.wordEmbedding(for: .english)
        let sentEmb = NLEmbedding.sentenceEmbedding(for: .english)

        // Warmup — one throwaway embedding to avoid cold-load inflation
        if let wordEmb {
            _ = Self.wordAveragedEmbedding("warmup call", using: wordEmb)
        }
        if let sentEmb {
            _ = sentEmb.vector(for: "warmup call")
        }

        // --- Train logistic head on training data ---
        var trainedHead = LogisticRegressionHead()
        var trainingTimeMs = 0.0
        let trainingCaseCount = Self.trainingCases.count

        if let wordEmb {
            // Embed all training cases
            var trainEmbeddings: [[Double]] = []
            var trainLabels: [Bool] = []

            for tc in Self.trainingCases {
                if let emb = Self.wordAveragedEmbedding(tc.input, using: wordEmb) {
                    trainEmbeddings.append(emb)
                    trainLabels.append(tc.expectedNeedsLLM)
                }
            }

            if !trainEmbeddings.isEmpty {
                let t0 = CFAbsoluteTimeGetCurrent()
                trainedHead = Self.trainLogisticHead(
                    embeddings: trainEmbeddings,
                    labels: trainLabels
                )
                let t1 = CFAbsoluteTimeGetCurrent()
                trainingTimeMs = (t1 - t0) * 1000.0
            }
        }

        // Fan-out: replicate the trained head N times (simulates multiple task-specific heads)
        let heads = (0..<Self.headCount).map { _ in trainedHead }

        var wordEmbTimes: [Double] = []
        var sentEmbTimes: [Double] = []
        var hcTimes: [Double] = []
        var singleHeadTimes: [Double] = []
        var fanOutEmbedTimes: [Double] = []
        var fanOutAllHeadsTimes: [Double] = []
        var fanOutPerHeadTimes: [Double] = []

        var hcCorrect = 0
        var trainedCorrect = 0
        var hcVsTrainedAgree = 0

        struct DiffStats {
            var count = 0
            var hcCorrect = 0
            var trainedCorrect = 0
            var agree = 0
        }
        var diffMap: [String: DiffStats] = [:]

        for tc in testCases {
            // 1. Word-averaged embedding time
            var embedding: [Double]?
            if let wordEmb {
                let t0 = CFAbsoluteTimeGetCurrent()
                embedding = Self.wordAveragedEmbedding(tc.input, using: wordEmb)
                let t1 = CFAbsoluteTimeGetCurrent()
                wordEmbTimes.append((t1 - t0) * 1000.0)
            }

            // 2. Sentence embedding time
            if let sentEmb {
                let t0 = CFAbsoluteTimeGetCurrent()
                _ = sentEmb.vector(for: tc.input)
                let t1 = CFAbsoluteTimeGetCurrent()
                sentEmbTimes.append((t1 - t0) * 1000.0)
            }

            // 3. Hand-crafted classifier time
            let t0hc = CFAbsoluteTimeGetCurrent()
            let (hcResult, _) = NeedsLLMClassifier.shared.classifyWithProbability(tc.input)
            let t1hc = CFAbsoluteTimeGetCurrent()
            hcTimes.append((t1hc - t0hc) * 1000.0)

            // 4. Trained head on embedding
            var trainedResult = false
            if let emb = embedding {
                let t0h = CFAbsoluteTimeGetCurrent()
                trainedResult = trainedHead.classify(emb)
                let t1h = CFAbsoluteTimeGetCurrent()
                singleHeadTimes.append((t1h - t0h) * 1000.0)
            }

            // 5. Fan-out: embed once + run all heads
            if let wordEmb {
                let t0e = CFAbsoluteTimeGetCurrent()
                let fanEmb = Self.wordAveragedEmbedding(tc.input, using: wordEmb)
                let t1e = CFAbsoluteTimeGetCurrent()
                fanOutEmbedTimes.append((t1e - t0e) * 1000.0)

                if let fanEmb {
                    let t0all = CFAbsoluteTimeGetCurrent()
                    for head in heads {
                        _ = head.classify(fanEmb)
                    }
                    let t1all = CFAbsoluteTimeGetCurrent()
                    let allMs = (t1all - t0all) * 1000.0
                    fanOutAllHeadsTimes.append(allMs)
                    fanOutPerHeadTimes.append(allMs / Double(heads.count))
                }
            }

            // Track accuracy / agreement
            let hcMatch = hcResult == tc.expectedNeedsLLM
            let trainedMatch = trainedResult == tc.expectedNeedsLLM
            let agree = hcResult == trainedResult
            if hcMatch { hcCorrect += 1 }
            if trainedMatch { trainedCorrect += 1 }
            if agree { hcVsTrainedAgree += 1 }

            var ds = diffMap[tc.difficulty, default: DiffStats()]
            ds.count += 1
            if hcMatch { ds.hcCorrect += 1 }
            if trainedMatch { ds.trainedCorrect += 1 }
            if agree { ds.agree += 1 }
            diffMap[tc.difficulty] = ds
        }

        let total = testCases.count
        let totalD = Double(total)

        let perDiff = diffMap.keys.sorted().map { key -> (String, Double, Double, Double, Int) in
            let s = diffMap[key]!
            return (
                key,
                s.count > 0 ? Double(s.hcCorrect) / Double(s.count) : 0,
                s.count > 0 ? Double(s.trainedCorrect) / Double(s.count) : 0,
                s.count > 0 ? Double(s.agree) / Double(s.count) : 0,
                s.count
            )
        }

        return ClassifierPipelineBenchmarkResult(
            totalCases: total,
            wordEmbedding: LatencyStats(from: wordEmbTimes),
            sentenceEmbedding: sentEmbTimes.isEmpty ? nil : LatencyStats(from: sentEmbTimes),
            handCrafted: LatencyStats(from: hcTimes),
            singleHead: LatencyStats(from: singleHeadTimes),
            fanOut: FanOutStats(
                headCount: Self.headCount,
                embedOnce: LatencyStats(from: fanOutEmbedTimes),
                allHeads: LatencyStats(from: fanOutAllHeadsTimes),
                perHead: LatencyStats(from: fanOutPerHeadTimes)
            ),
            hcAccuracy: totalD > 0 ? Double(hcCorrect) / totalD : 0,
            hcCorrect: hcCorrect,
            trainedHeadAccuracy: totalD > 0 ? Double(trainedCorrect) / totalD : 0,
            trainedHeadCorrect: trainedCorrect,
            hcVsTrainedAgreement: totalD > 0 ? Double(hcVsTrainedAgree) / totalD : 0,
            hcVsTrainedAgree: hcVsTrainedAgree,
            trainingTimeMs: trainingTimeMs,
            trainingCaseCount: trainingCaseCount,
            perDifficulty: perDiff
        )
    }

    // MARK: - Console Output

    public func printResults(_ result: ClassifierPipelineBenchmarkResult) {
        let n = result.totalCases
        let h = result.fanOut.headCount
        print("")
        print("CLASSIFIER PIPELINE BENCHMARK (\(n) cases, trained head)")
        print(String(repeating: "─", count: 54))

        func fmt(_ ms: Double) -> String { String(format: "%.2fms", ms) }

        print("EMBEDDING         median    p95")
        print("  Word-Averaged   \(fmt(result.wordEmbedding.median).padding(toLength: 10, withPad: " ", startingAt: 0))\(fmt(result.wordEmbedding.p95))")
        if let se = result.sentenceEmbedding {
            print("  Sentence-Level  \(fmt(se.median).padding(toLength: 10, withPad: " ", startingAt: 0))\(fmt(se.p95))")
        } else {
            print("  Sentence-Level  (unavailable)")
        }

        print("")
        print("CLASSIFIER        median    p95")
        print("  Hand-Crafted    \(fmt(result.handCrafted.median).padding(toLength: 10, withPad: " ", startingAt: 0))\(fmt(result.handCrafted.p95))")
        print("  Trained Head    \(fmt(result.singleHead.median).padding(toLength: 10, withPad: " ", startingAt: 0))\(fmt(result.singleHead.p95))")
        print("  Fan-Out (\(h))     \(fmt(result.fanOut.allHeads.median).padding(toLength: 10, withPad: " ", startingAt: 0))\(fmt(result.fanOut.allHeads.p95))")

        print("")
        print("TRAINING")
        print("  Cases:          \(result.trainingCaseCount)")
        print("  Time:           \(String(format: "%.1fms", result.trainingTimeMs))")

        print("")
        print("ACCURACY (vs labels)")
        print("  Hand-Crafted:   \(String(format: "%.1f%%", result.hcAccuracy * 100)) (\(result.hcCorrect)/\(n))")
        print("  Trained Head:   \(String(format: "%.1f%%", result.trainedHeadAccuracy * 100)) (\(result.trainedHeadCorrect)/\(n))")

        print("")
        print("AGREEMENT")
        print("  HC vs Trained:  \(String(format: "%.1f%%", result.hcVsTrainedAgreement * 100)) (\(result.hcVsTrainedAgree)/\(n))")

        if !result.perDifficulty.isEmpty {
            print("")
            print("PER DIFFICULTY")
            for (diff, hcAcc, trainedAcc, agree, count) in result.perDifficulty {
                let d = diff.padding(toLength: 10, withPad: " ", startingAt: 0)
                let hcPct = String(format: "%3.0f%%", hcAcc * 100)
                let trPct = String(format: "%3.0f%%", trainedAcc * 100)
                let agPct = String(format: "%3.0f%%", agree * 100)
                print("  \(d) HC:\(hcPct)  Trained:\(trPct)  Agree:\(agPct)  (n=\(count))")
            }
        }

        print(String(repeating: "─", count: 54))
        print("")
    }

    // MARK: - Embedding Helpers

    private static func wordAveragedEmbedding(_ text: String, using embedding: NLEmbedding) -> [Double]? {
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard !words.isEmpty else { return nil }

        var sumVector: [Double]?
        var wordCount = 0

        for word in words {
            if let vector = embedding.vector(for: word) {
                if sumVector == nil {
                    sumVector = vector
                } else {
                    for i in 0..<vector.count {
                        sumVector![i] += vector[i]
                    }
                }
                wordCount += 1
            }
        }

        guard let sum = sumVector, wordCount > 0 else { return nil }
        return sum.map { $0 / Double(wordCount) }
    }

    // MARK: - Training

    private static func trainLogisticHead(
        embeddings: [[Double]],
        labels: [Bool],
        lr: Double = 0.1,
        lambda: Double = 0.01,
        maxEpochs: Int = 500,
        convergenceTolerance: Double = 1e-6
    ) -> LogisticRegressionHead {
        let n = embeddings.count
        guard n > 0 else { return LogisticRegressionHead() }
        let dim = embeddings[0].count
        let invN = 1.0 / Double(n)

        // Compute mean and std for standardization
        var mean = [Double](repeating: 0, count: dim)
        for emb in embeddings {
            for j in 0..<dim { mean[j] += emb[j] }
        }
        for j in 0..<dim { mean[j] *= invN }

        var variance = [Double](repeating: 0, count: dim)
        for emb in embeddings {
            for j in 0..<dim {
                let diff = emb[j] - mean[j]
                variance[j] += diff * diff
            }
        }
        var stddev = [Double](repeating: 0, count: dim)
        for j in 0..<dim {
            stddev[j] = sqrt(variance[j] * invN)
            if stddev[j] < 1e-10 { stddev[j] = 1.0 }
        }

        // Standardize and flatten into contiguous row-major array (n × dim)
        var flatX = [Double](repeating: 0, count: n * dim)
        for i in 0..<n {
            let offset = i * dim
            for j in 0..<dim {
                flatX[offset + j] = (embeddings[i][j] - mean[j]) / stddev[j]
            }
        }
        let y = labels.map { $0 ? 1.0 : 0.0 }

        // Batch gradient descent using BLAS
        var w = [Double](repeating: 0, count: dim)
        var b = 0.0
        var prevLoss = Double.infinity

        for _ in 0..<maxEpochs {
            // 1. logits = X * w + b  (BLAS matrix-vector multiply)
            var logits = [Double](repeating: b, count: n)
            cblas_dgemv(CblasRowMajor, CblasNoTrans,
                        Int32(n), Int32(dim),
                        1.0, flatX, Int32(dim),
                        w, 1,
                        1.0, &logits, 1)

            // 2. sigmoid → errors, cross-entropy loss
            var errors = [Double](repeating: 0, count: n)
            var loss = 0.0
            for i in 0..<n {
                let p = 1.0 / (1.0 + exp(-logits[i]))
                errors[i] = p - y[i]
                loss += -y[i] * log(Swift.max(p, 1e-15)) - (1.0 - y[i]) * log(Swift.max(1.0 - p, 1e-15))
            }
            loss *= invN

            // L2 regularization loss
            var l2 = 0.0
            vDSP_dotprD(w, 1, w, 1, &l2, vDSP_Length(dim))
            loss += 0.5 * lambda * l2 * invN

            // 3. gradW = (1/n) * X^T * errors  (BLAS)
            var gradW = [Double](repeating: 0, count: dim)
            cblas_dgemv(CblasRowMajor, CblasTrans,
                        Int32(n), Int32(dim),
                        invN, flatX, Int32(dim),
                        errors, 1,
                        0.0, &gradW, 1)

            // Add L2 gradient: gradW += (lambda/n) * w
            cblas_daxpy(Int32(dim), lambda * invN, w, 1, &gradW, 1)

            // 4. w -= lr * gradW  (BLAS)
            cblas_daxpy(Int32(dim), -lr, gradW, 1, &w, 1)

            // 5. Bias update
            var gradB = 0.0
            for e in errors { gradB += e }
            gradB *= invN
            b -= lr * gradB

            if abs(prevLoss - loss) < convergenceTolerance { break }
            prevLoss = loss
        }

        // Un-transform so head works on raw embeddings
        var rawWeights = [Double](repeating: 0, count: dim)
        var rawBias = b
        for j in 0..<dim {
            rawWeights[j] = w[j] / stddev[j]
            rawBias -= w[j] * mean[j] / stddev[j]
        }

        return LogisticRegressionHead(weights: rawWeights, bias: rawBias)
    }

    // MARK: - Training Cases (120: 30 clean, 30 fuzzy, 30 natural, 30 chaotic)

    public static let trainingCases: [ClassifierPipelineTestCase] = [
        // ── Clean (protocol-heavy, no LLM needed) ── 30 cases
        ClassifierPipelineTestCase(input: "ssh space dash i space tilde slash dot ssh slash id underscore rsa space root at one nine two dot one six eight dot one dot one", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "curl space dash capital X space all caps POST space dash capital H space quote capital Content dash capital Type colon space application slash json quote space https colon slash slash api dot example dot com slash v one slash users", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "terraform space plan space dash var dash file equals production dot tfvars", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "export space all caps DATABASE underscore URL equals quote postgres colon slash slash admin colon secret at localhost colon five four three two slash mydb quote", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "rsync space dash a v z space dash e space ssh space dot slash dist slash space user at one seven two dot sixteen dot zero dot one colon slash var slash www slash", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "redis dash cli space dash h space one two seven dot zero dot zero dot one space dash p space six three seven nine space all caps PING", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "make space dash j space eight space all caps CC equals gcc space all caps CFLAGS equals quote dash capital O two dash capital Wall quote", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "cargo space build space dash dash release space dash dash target space x eighty six underscore sixty four dash unknown dash linux dash gnu", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "go space build space dash o space bin slash server space dot slash cmd slash server", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "swift space build space dash c space release space dash dash triple space arm sixty four dash apple dash macosx", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "aws space s three space cp space s three colon slash slash my dash bucket slash data dot csv space dot slash", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "ffmpeg space dash i space input dot mp four space dash vf space quote scale equals one nine twenty colon one zero eighty quote space dash c colon a space copy space output dot mp four", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "openssl space req space dash x five zero nine space dash newkey space rsa colon four zero nine six space dash keyout space key dot pem space dash out space cert dot pem space dash days space three six five", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "camel case get user profile", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "snake case api response handler", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "pascal case user authentication service", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "kebab case my awesome component", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "git space log space dash dash oneline space dash dash graph space dash n space twenty", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "docker space compose space dash f space docker dash compose dot prod dot yml space up space dash d", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "python space dash m space venv space dot venv space ampersand ampersand space source space dot venv slash bin slash activate", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "pip space install space dash r space requirements dot txt space dash dash upgrade", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "grep space dash r space dash n space dash i space quote all caps TODO quote space dot slash src slash", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "tar space dash x z f space archive dot tar dot gz space dash capital C space slash opt slash app", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "find space dot space dash name space quote star dot log quote space dash mtime space plus seven space dash delete", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "echo space dollar all caps HOME slash dot config slash app dot yml", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "sed space dash i space quote s slash old dash text slash new dash text slash g quote space config dot yaml", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "awk space quote open brace print space dollar two close brace quote space data dot tsv", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "xcodebuild space dash workspace space capital Talkie dot xcworkspace space dash scheme space capital Talkie space dash configuration space capital Release", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "git space remote space add space upstream space https colon slash slash github dot com slash owner slash repo dot git", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "scp space dash capital P space two two zero two space user at ten dot zero dot zero dot five colon slash tmp slash dump dot sql space dot slash", expectedNeedsLLM: false, difficulty: "clean"),

        // ── Fuzzy (synonym substitutions, needs LLM) ── 30 cases
        ClassifierPipelineTestCase(input: "grep asterisk period log forward slash var forward slash log forward slash", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "curl minus capital X capital POST minus capital H content hyphen type colon application forward slash json", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "git diff double dash staged", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "tar minus xzf backup period tar period gz", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "find period minus name asterisk period py minus type f", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "export capital NODE underscore capital ENV equals sign production", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "kubectl get pods minus n default double dash output json", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "chmod seven five five script period sh", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "pip install flask equals sign equals sign two period zero period zero", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "git checkout minus b feature forward slash auth", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "docker compose up minus d double dash build", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "psql minus capital U postgres minus d mydb minus c quote select asterisk from users quote", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "scp file period txt user at sign one ninety two period one sixty eight period one period one hundred colon tilde forward slash", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "git log double dash oneline minus n ten", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "brew install double dash cask firefox", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "rsync minus avz period forward slash source forward slash user at sign host colon forward slash dest forward slash", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "aws s3 sync period forward slash build forward slash s3 colon forward slash forward slash my hyphen bucket forward slash static", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "camelcase handle form submit", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "snake_case max retry count", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "git stash pop at sign open brace zero close brace", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "backslash n backslash t hello world", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "echo dollar sign open parenthesis date close parenthesis", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "ffmpeg minus i input period mov minus codec copy output period mp4", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "terraform apply minus auto hyphen approve", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "go test period forward slash period period period minus v minus race", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "cargo run double dash double dash release", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "git rebase minus minus interactive capital HEAD tilde three", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "nginx minus t ampersand ampersand systemctl reload nginx", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "sed minus i quote s forward slash http forward slash https forward slash g quote config period yml", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "curl minus s minus o forward slash dev forward slash null minus w quote percent open brace http underscore code close brace quote http colon forward slash forward slash localhost colon three thousand", expectedNeedsLLM: true, difficulty: "fuzzy"),

        // ── Natural (conversational wrapping, needs LLM) ── 30 cases
        ClassifierPipelineTestCase(input: "basically run git space fetch space dash dash all space ampersand ampersand space git space pull", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "I think we need kubectl space scale space deployment slash api space dash dash replicas equals three", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "right so set it to snake case max connection pool size", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "type out ssh space dash capital L space eight zero eight zero colon localhost colon five four three two space bastion", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "so for the environment variable it's all caps AWS underscore SECRET underscore ACCESS underscore KEY", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "the terraform command should be terraform space init space dash backend dash config equals quote key equals prod slash terraform dot tfstate quote", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "okay let me type the curl command so it's curl space dash s space dash capital H space quote all caps Authorization colon space capital Bearer space dollar all caps TOKEN quote space https colon slash slash api dot example dot com slash me", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "I want to run docker space exec space dash it space postgres underscore db space psql space dash capital U space admin", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "um so the function is called pascal case create payment intent", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "let's see we need to do pip space install space dash e space dot open bracket dev close bracket", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "the redis command I want is redis dash cli space dash dash scan space match space quote session colon star quote", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "so basically what we wanna run is git space cherry dash pick space dash dash no dash commit space abc one two three four", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "and the port number should be colon three thousand", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "alright change the class name to pascal case authenticated user session", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "I need the output piped to jq space dot open bracket close bracket dot name", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "set the variable to dollar open brace all caps HOME close brace slash dot config slash app dot toml", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "like the regex pattern is caret open bracket a dash z A dash Z close bracket plus dollar", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "for the flag use dash dash dry dash run please", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "so the full path is tilde slash capital Library slash capital Application space capital Support slash capital Talkie slash talkie dot sqlite", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "go ahead and type git space reset space dash dash soft space capital HEAD tilde one", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "let me think um yeah the image tag is my dash registry dot io slash api colon v two dot one dash rc one", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "make it cargo space test space dash dash lib space dash dash space dash dash test dash threads space one", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "we should set the cron to star space star slash two space star space star space star", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "the nginx location block should match tilde space caret slash api slash v open bracket zero dash nine close bracket plus", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "and at the end redirect with two greater than space slash dev slash null", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "I need to add the alias um alias space ll equals quote ls space dash la quote to my bashrc", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "run it with like xargs space dash capital I space open brace close brace space cp space open brace close brace space backup slash", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "the go struct tag should be json colon quote camel case user name comma omitempty quote", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "so like make the webpack config output to dist slash open bracket name close bracket dot open bracket contenthash colon eight close bracket dot js", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "we want to write iptables minus capital A capital INPUT minus p tcp double dash dport four four three minus j all caps ACCEPT", expectedNeedsLLM: true, difficulty: "natural"),

        // ── Chaotic (corrections, false starts, needs LLM) ── 30 cases
        ClassifierPipelineTestCase(input: "open curly brace newline tab quote name quote colon quote capital John quote comma newline tab quote age quote colon twenty five newline close curly brace", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "the connection string is postgres colon slash slash wait what was the password oh right admin colon p at sign s s w zero r d at localhost colon five four three two slash production underscore db", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "three files in the directory", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "port eighty four forty three I mean port eight four four three", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "the address is like http no https colon slash slash api dot production dot our company dot com slash v three slash webhook", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "so I need to pipe it through like four commands cat the file then grep for errors then sort then unique with count so cat space log dot txt space pipe space grep space error space pipe space sort space pipe space uniq space dash c", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "the docker tag is ghcr dot io slash my org slash my app colon sha dash wait how do you say git sha... the sha prefix", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "okay write open bracket open bracket colon minus s colon minus d close bracket close bracket double ampersand echo pass pipe pipe echo fail", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "no no no go back the command was git diff HEAD tilde two dot dot HEAD that's HEAD tilde the number two then two dots then HEAD", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "I need an awk command to... you know what just do awk space quote open brace if dollar three greater than one hundred print dollar zero close brace quote space data dot csv", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "the method signature is func space camel case fetch user open paren underscore id colon capital String close paren space async space throws space dash greater than capital User", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "umm set the crontab to... it should run every fifteen minutes so star slash fifteen space star space star space star space star", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "the kubernetes label selector is app equals my dash app comma version in open paren v one comma v two close paren", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "type the regex... hmm it's like caret open bracket A dash Z close bracket open bracket a dash z A dash Z zero dash nine close bracket star at sign open bracket a dash z close bracket plus backslash dot open bracket a dash z close bracket open brace two comma close brace dollar", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "git rebase onto main the commit from tuesday I think it was like a b c one two three four five six seven", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "webpack serve open paren or is it webpack dash dev dash server I always forget close paren with dash dash hot and dash dash port nine thousand", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "the nginx config upstream block upstream space my underscore backend space open curly brace newline space space server space one two seven dot zero dot zero dot one colon three thousand weight equals five semicolon newline space space server space one two seven dot zero dot zero dot one colon three thousand one weight equals three semicolon newline close curly brace", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "the TypeScript type is capital Record less than string comma Array less than open curly brace id colon number semicolon name colon string close curly brace greater than greater than", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "wait I need to escape the dollar signs in the dockerfile so it's backslash dollar open paren cat slash run slash secrets slash db underscore password close paren", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "do the curl but like with retries so curl space dash dash retry space three space dash dash retry dash delay space two space then the url", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "the swift property wrapper at capital Published var camel case selected tab colon capital Tab equals dot home", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "ssh minus capital J jump dash host user at final dash host so that's proxy jumping through the bastion", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "actually scratch what I said before just do a simple ls minus la slash tmp", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "the helm values should be set dash dash set image dot tag equals v one dot four dot two dash rc one and set dash dash set replicas equals three", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "open bracket dollar open paren date plus percent capital Y minus percent m minus percent d close paren close bracket underscore backup dot sql", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "the go generics syntax is func capital Map open bracket capital T any comma capital U any close bracket open paren slice open bracket close bracket capital T comma fn func open paren capital T close paren capital U close paren open bracket close bracket capital U", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "I want to write the SQL query but like dynamically so select star from users where created underscore at greater than dollar one and status equals quote active quote order by id limit dollar two", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "the whole pipeline is cat access dot log pipe grep five hundred pipe awk open brace print dollar one close brace pipe sort pipe uniq minus c pipe sort minus r n pipe head minus five", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "for the terraform block it's resource quote aws underscore lambda underscore function quote quote my underscore function quote", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "I keep getting the args wrong okay the ffmpeg command is ffmpeg minus i concat colon file one dot ts pipe file two dot ts minus c copy output dot mp four", expectedNeedsLLM: true, difficulty: "chaotic"),
    ]

    // MARK: - Test Cases (40: 10 clean, 10 fuzzy, 10 natural, 10 chaotic)

    public static let testCases: [ClassifierPipelineTestCase] = [
        // ── Clean (protocol-heavy, no LLM needed) ──
        ClassifierPipelineTestCase(input: "git space push space dash u space origin space main", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "docker space run space dash dash rm space dash p space eight zero eight zero colon eight zero space nginx", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "npm space install space dash capital D space typescript at five", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "kubectl space get space pods space dash n space kube dash system", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "chmod space zero seven five five space slash usr slash local slash bin slash deploy dot sh", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "brew space install space dash dash cask space visual dash studio dash code", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "systemctl space restart space nginx dot service", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "cargo space build space dash dash release", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "psql space dash h space localhost space dash capital U space postgres space dash d space production", expectedNeedsLLM: false, difficulty: "clean"),
        ClassifierPipelineTestCase(input: "rsync space dash a v z space dash e space ssh space dot slash dist slash", expectedNeedsLLM: false, difficulty: "clean"),

        // ── Fuzzy (synonym substitutions, needs LLM) ──
        ClassifierPipelineTestCase(input: "git commit minus m quote fix login bug quote", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "ls minus l minus a slash var slash log", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "cat file period txt", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "cd forward slash usr forward slash local forward slash bin", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "python server period py double dash port eight thousand", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "git push hyphen u origin main", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "npm install hyphen hyphen save dev eslint", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "echo hashtag this is a comment", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "docker run minus minus rm minus it ubuntu", expectedNeedsLLM: true, difficulty: "fuzzy"),
        ClassifierPipelineTestCase(input: "ssh minus i tilde forward slash period ssh forward slash key period pem user at sign server", expectedNeedsLLM: true, difficulty: "fuzzy"),

        // ── Natural (conversational wrapping, needs LLM) ──
        ClassifierPipelineTestCase(input: "okay so the command is git space push space dash u space origin space main", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "I wanna set the variable name to camel case get user profile", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "change that to snake case api response handler", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "the path should be slash usr slash local slash bin", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "make it all caps DATABASE underscore URL", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "can you type out docker space run space dash dash rm space nginx", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "so like the function name would be camel case handle click event", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "let's do npm space install space dash capital D space typescript", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "um the flag is dash dash verbose", expectedNeedsLLM: true, difficulty: "natural"),
        ClassifierPipelineTestCase(input: "and then pipe it to grep space dash i space error", expectedNeedsLLM: true, difficulty: "natural"),

        // ── Chaotic (corrections, false starts, needs LLM) ──
        ClassifierPipelineTestCase(input: "dash dash no wait just dash v", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "the API endpoint is slash api slash v two slash users slash colon id", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "so we need to... actually let's just do git stash", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "run it on port three thousand", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "camel case is authenticated", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "just the flag dash dash dry dash run", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "wait no not dash dash force I meant dash dash force dash with dash lease", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "kubectl get pods no actually I want kubectl get deployments dash o wide", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "um okay so like the variable name should be um camel case handle submit and then no wait pascal case handle submit because it's a component", expectedNeedsLLM: true, difficulty: "chaotic"),
        ClassifierPipelineTestCase(input: "type ssh at sign root at the server at one ninety two dot one sixty eight dot one dot fifty", expectedNeedsLLM: true, difficulty: "chaotic"),
    ]
}
