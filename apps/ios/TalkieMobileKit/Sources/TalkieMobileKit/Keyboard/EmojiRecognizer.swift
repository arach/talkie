//
//  EmojiRecognizer.swift
//  TalkieMobileKit
//
//  Voice-to-emoji recognition using NLEmbedding for semantic similarity matching.
//  Say "love" and get a heart. Say "laughing" and get tears of joy.
//

import Foundation
import NaturalLanguage

// MARK: - Emoji Mapping

/// Maps emojis to their semantic descriptions for embedding comparison
private struct EmojiPhraseMapping {
    let emoji: String
    let phrases: [String]

    /// Get category for an emoji based on the emoji character
    static func category(for emoji: String) -> EmojiCategory {
        // Faces & Emotions
        let faces = "😊😃😄😁😂🤣😅😆🥹🥰😍🤩😎🤓😜😛🤪😏🙃😢😭🥺😞😔😿😠😡🤬😤😮😲🤯😱🤔🧐😕🤷🤢🤮🤒😷😴🥱😪🙄🤫🤭🫣🫡🤡💀👻"
        // Hearts & Love
        let hearts = "❤️🧡💛💚💙💜🖤🤍💕💗💓💔❤️‍🔥"
        // Gestures & Hands
        let gestures = "👍👎👏🙌🙏🤝✌️🤞🤟🤘👌🤌👋💪🫶👊✊👆👇👈👉"
        // Symbols & Status
        let symbols = "✅❌⭐🌟💯🔥✨💥⚡🎉🥳🎊🏆🥇🎯💡⚠️🚫❓❗💤💬💭👀👁️"
        // Nature & Weather
        let nature = "☀️🌙🌈☁️🌧️❄️🌊🌸🌺🌹🌻🍀🌲🌴"
        // Animals
        let animals = "🐶🐱🐻🦊🦁🐯🦄🐸🐵🙈🙉🙊🐔🦆🐷🐮🐴🦋🐝🐛🦀🐙🦈🐬🐳🦅🦉🐍🐢"
        // Food & Drink
        let food = "🍕🍔🍟🌮🌯🍣🍜🍦🍩🍪🎂🍰☕🍺🍷🥂🍎🍌🍇🍓🥑🥕🌶️🧀"
        // Activities & Objects
        let activities = "⚽🏀🎮🎬🎵🎸🎤📱💻📸🔑💰💵💎🎁📦✈️🚗🏠⏰📅📝✏️📚🔒🔓"

        if faces.contains(emoji) { return .faces }
        if hearts.contains(emoji) { return .hearts }
        if gestures.contains(emoji) { return .gestures }
        if symbols.contains(emoji) { return .symbols }
        if nature.contains(emoji) { return .nature }
        if animals.contains(emoji) { return .animals }
        if food.contains(emoji) { return .food }
        if activities.contains(emoji) { return .activities }

        return .symbols // Default fallback
    }

    static let all: [EmojiPhraseMapping] = [
        // MARK: - Faces & Emotions

        // Happy
        EmojiPhraseMapping(emoji: "😊", phrases: [
            "smile", "happy", "glad", "pleased", "content", "joyful", "cheerful", "smiling"
        ]),
        EmojiPhraseMapping(emoji: "😃", phrases: [
            "grin", "big smile", "very happy", "excited", "thrilled", "grinning"
        ]),
        EmojiPhraseMapping(emoji: "😄", phrases: [
            "laughing eyes", "happy eyes", "beaming", "radiant"
        ]),
        EmojiPhraseMapping(emoji: "😁", phrases: [
            "teeth", "showing teeth", "cheesy grin", "cheese"
        ]),
        EmojiPhraseMapping(emoji: "😂", phrases: [
            "crying laughing", "tears of joy", "lol", "so funny", "hilarious", "laughing hard", "dying laughing", "lmao", "rofl"
        ]),
        EmojiPhraseMapping(emoji: "🤣", phrases: [
            "rolling on floor", "rofl", "extremely funny", "can't stop laughing"
        ]),
        EmojiPhraseMapping(emoji: "😅", phrases: [
            "nervous laugh", "awkward", "sweat smile", "relief", "phew"
        ]),
        EmojiPhraseMapping(emoji: "😆", phrases: [
            "squinting laugh", "haha", "laughing out loud"
        ]),
        EmojiPhraseMapping(emoji: "🥹", phrases: [
            "holding back tears", "touched", "emotional", "moved", "aww", "about to cry happy"
        ]),
        EmojiPhraseMapping(emoji: "🥰", phrases: [
            "love face", "adoring", "hearts around face", "feeling loved", "in love face"
        ]),
        EmojiPhraseMapping(emoji: "😍", phrases: [
            "heart eyes", "in love", "loving it", "beautiful", "gorgeous", "stunning"
        ]),
        EmojiPhraseMapping(emoji: "🤩", phrases: [
            "star eyes", "starstruck", "amazed", "impressed", "wow eyes", "celebrity"
        ]),

        // Cool & Confident
        EmojiPhraseMapping(emoji: "😎", phrases: [
            "cool", "sunglasses", "awesome", "chill", "confident", "swagger"
        ]),
        EmojiPhraseMapping(emoji: "🤓", phrases: [
            "nerd", "nerdy", "geek", "geeky", "smart", "glasses"
        ]),

        // Playful
        EmojiPhraseMapping(emoji: "😜", phrases: [
            "wink tongue", "playful", "joking", "teasing", "silly"
        ]),
        EmojiPhraseMapping(emoji: "😛", phrases: [
            "tongue out", "bleh", "raspberry", "silly face"
        ]),
        EmojiPhraseMapping(emoji: "🤪", phrases: [
            "crazy", "wild", "zany", "goofy", "wacky", "nuts"
        ]),
        EmojiPhraseMapping(emoji: "😏", phrases: [
            "smirk", "smug", "suggestive", "sly", "flirty", "knowing"
        ]),
        EmojiPhraseMapping(emoji: "🙃", phrases: [
            "upside down", "sarcastic", "ironic", "whatever", "passive aggressive"
        ]),

        // Sad & Crying
        EmojiPhraseMapping(emoji: "😢", phrases: [
            "crying", "tear", "sad", "upset", "unhappy", "disappointed"
        ]),
        EmojiPhraseMapping(emoji: "😭", phrases: [
            "sobbing", "bawling", "crying hard", "very sad", "devastated", "wailing"
        ]),
        EmojiPhraseMapping(emoji: "🥺", phrases: [
            "pleading", "puppy eyes", "please", "begging", "cute sad", "pwease"
        ]),
        EmojiPhraseMapping(emoji: "😞", phrases: [
            "disappointed", "let down", "dejected", "bummed"
        ]),
        EmojiPhraseMapping(emoji: "😔", phrases: [
            "pensive", "thoughtful sad", "melancholy", "down"
        ]),
        EmojiPhraseMapping(emoji: "😿", phrases: [
            "crying cat", "sad cat", "cat tears"
        ]),

        // Angry & Frustrated
        EmojiPhraseMapping(emoji: "😠", phrases: [
            "angry", "mad", "annoyed", "irritated", "pissed"
        ]),
        EmojiPhraseMapping(emoji: "😡", phrases: [
            "very angry", "furious", "rage", "fuming", "livid", "red face angry"
        ]),
        EmojiPhraseMapping(emoji: "🤬", phrases: [
            "cursing", "swearing", "expletive", "symbols mouth", "censored"
        ]),
        EmojiPhraseMapping(emoji: "😤", phrases: [
            "huffing", "frustrated", "steam nose", "determined angry"
        ]),

        // Surprised & Shocked
        EmojiPhraseMapping(emoji: "😮", phrases: [
            "surprised", "open mouth", "oh", "wow"
        ]),
        EmojiPhraseMapping(emoji: "😲", phrases: [
            "astonished", "shocked", "stunned", "gasping"
        ]),
        EmojiPhraseMapping(emoji: "🤯", phrases: [
            "mind blown", "exploding head", "unbelievable", "crazy", "blown away"
        ]),
        EmojiPhraseMapping(emoji: "😱", phrases: [
            "screaming", "terrified", "horror", "scared", "frightened", "omg"
        ]),

        // Thinking & Confused
        EmojiPhraseMapping(emoji: "🤔", phrases: [
            "thinking", "hmm", "wondering", "pondering", "considering", "curious"
        ]),
        EmojiPhraseMapping(emoji: "🧐", phrases: [
            "monocle", "inspecting", "examining", "scrutinizing", "investigating"
        ]),
        EmojiPhraseMapping(emoji: "😕", phrases: [
            "confused", "puzzled", "uncertain", "unsure"
        ]),
        EmojiPhraseMapping(emoji: "🤷", phrases: [
            "shrug", "don't know", "whatever", "idk", "no idea", "who knows"
        ]),

        // Sick & Unwell
        EmojiPhraseMapping(emoji: "🤢", phrases: [
            "nauseous", "sick", "queasy", "gross", "disgusted", "about to vomit"
        ]),
        EmojiPhraseMapping(emoji: "🤮", phrases: [
            "vomit", "throwing up", "puke", "barf", "disgusting"
        ]),
        EmojiPhraseMapping(emoji: "🤒", phrases: [
            "sick", "fever", "thermometer", "ill", "unwell"
        ]),
        EmojiPhraseMapping(emoji: "😷", phrases: [
            "mask", "sick mask", "covid", "medical mask", "flu"
        ]),

        // Sleep & Tired
        EmojiPhraseMapping(emoji: "😴", phrases: [
            "sleeping", "asleep", "zzz", "tired", "sleepy"
        ]),
        EmojiPhraseMapping(emoji: "🥱", phrases: [
            "yawning", "bored", "tired", "yawn", "sleepy"
        ]),
        EmojiPhraseMapping(emoji: "😪", phrases: [
            "sleepy", "drowsy", "drooling sleep"
        ]),

        // Other Faces
        EmojiPhraseMapping(emoji: "🙄", phrases: [
            "eye roll", "rolling eyes", "whatever", "annoyed", "ugh", "seriously"
        ]),
        EmojiPhraseMapping(emoji: "🤫", phrases: [
            "shush", "quiet", "secret", "shh", "hush", "whisper"
        ]),
        EmojiPhraseMapping(emoji: "🤭", phrases: [
            "oops", "giggling", "covering mouth", "tee hee", "embarrassed laugh"
        ]),
        EmojiPhraseMapping(emoji: "🫣", phrases: [
            "peeking", "can't look", "covering eyes", "scared to look"
        ]),
        EmojiPhraseMapping(emoji: "🫡", phrases: [
            "salute", "yes sir", "roger", "respect", "at your service"
        ]),
        EmojiPhraseMapping(emoji: "🤡", phrases: [
            "clown", "foolish", "joker", "silly", "circus"
        ]),
        EmojiPhraseMapping(emoji: "💀", phrases: [
            "skull", "dead", "i'm dead", "dying", "skeleton", "rip"
        ]),
        EmojiPhraseMapping(emoji: "👻", phrases: [
            "ghost", "spooky", "boo", "halloween", "scary"
        ]),

        // MARK: - Hearts & Love

        EmojiPhraseMapping(emoji: "❤️", phrases: [
            "heart", "love", "red heart", "i love you", "romance", "affection"
        ]),
        EmojiPhraseMapping(emoji: "🧡", phrases: [
            "orange heart", "warm love"
        ]),
        EmojiPhraseMapping(emoji: "💛", phrases: [
            "yellow heart", "friendship", "friend love"
        ]),
        EmojiPhraseMapping(emoji: "💚", phrases: [
            "green heart", "nature love", "jealousy"
        ]),
        EmojiPhraseMapping(emoji: "💙", phrases: [
            "blue heart", "trust", "loyalty"
        ]),
        EmojiPhraseMapping(emoji: "💜", phrases: [
            "purple heart", "compassion", "purple love"
        ]),
        EmojiPhraseMapping(emoji: "🖤", phrases: [
            "black heart", "dark love", "emo", "goth"
        ]),
        EmojiPhraseMapping(emoji: "🤍", phrases: [
            "white heart", "pure love", "innocence"
        ]),
        EmojiPhraseMapping(emoji: "💕", phrases: [
            "two hearts", "love", "hearts"
        ]),
        EmojiPhraseMapping(emoji: "💗", phrases: [
            "growing heart", "increasing love"
        ]),
        EmojiPhraseMapping(emoji: "💓", phrases: [
            "beating heart", "heartbeat", "pounding heart"
        ]),
        EmojiPhraseMapping(emoji: "💔", phrases: [
            "broken heart", "heartbreak", "sad love", "breakup"
        ]),
        EmojiPhraseMapping(emoji: "❤️‍🔥", phrases: [
            "heart on fire", "passionate", "burning love", "hot love"
        ]),

        // MARK: - Gestures & Hands

        EmojiPhraseMapping(emoji: "👍", phrases: [
            "thumbs up", "like", "good", "yes", "okay", "approve", "agree", "nice"
        ]),
        EmojiPhraseMapping(emoji: "👎", phrases: [
            "thumbs down", "dislike", "bad", "no", "disapprove", "disagree", "boo"
        ]),
        EmojiPhraseMapping(emoji: "👏", phrases: [
            "clap", "clapping", "applause", "bravo", "well done", "congrats"
        ]),
        EmojiPhraseMapping(emoji: "🙌", phrases: [
            "hands up", "celebration", "praise", "hallelujah", "yay"
        ]),
        EmojiPhraseMapping(emoji: "🙏", phrases: [
            "pray", "please", "thank you", "thanks", "grateful", "hope", "namaste", "folded hands"
        ]),
        EmojiPhraseMapping(emoji: "🤝", phrases: [
            "handshake", "deal", "agreement", "partnership", "cooperation"
        ]),
        EmojiPhraseMapping(emoji: "✌️", phrases: [
            "peace", "victory", "two fingers", "peace sign"
        ]),
        EmojiPhraseMapping(emoji: "🤞", phrases: [
            "fingers crossed", "hope", "good luck", "wishing"
        ]),
        EmojiPhraseMapping(emoji: "🤟", phrases: [
            "rock on", "love you", "rock", "metal", "i love you hand"
        ]),
        EmojiPhraseMapping(emoji: "🤘", phrases: [
            "rock", "metal", "horns", "devil horns"
        ]),
        EmojiPhraseMapping(emoji: "👌", phrases: [
            "ok", "perfect", "okay sign", "chef's kiss", "precise"
        ]),
        EmojiPhraseMapping(emoji: "🤌", phrases: [
            "pinched fingers", "italian", "what do you want", "perfection"
        ]),
        EmojiPhraseMapping(emoji: "👋", phrases: [
            "wave", "hi", "hello", "bye", "goodbye", "waving"
        ]),
        EmojiPhraseMapping(emoji: "💪", phrases: [
            "muscle", "strong", "strength", "flex", "bicep", "power", "gym"
        ]),
        EmojiPhraseMapping(emoji: "🫶", phrases: [
            "heart hands", "love gesture", "hand heart"
        ]),
        EmojiPhraseMapping(emoji: "👊", phrases: [
            "fist bump", "punch", "fist", "bro"
        ]),
        EmojiPhraseMapping(emoji: "✊", phrases: [
            "raised fist", "solidarity", "power", "fight"
        ]),
        EmojiPhraseMapping(emoji: "👆", phrases: [
            "point up", "this", "above", "pointing up"
        ]),
        EmojiPhraseMapping(emoji: "👇", phrases: [
            "point down", "below", "pointing down"
        ]),
        EmojiPhraseMapping(emoji: "👈", phrases: [
            "point left", "that way", "pointing left"
        ]),
        EmojiPhraseMapping(emoji: "👉", phrases: [
            "point right", "pointing right", "look"
        ]),

        // MARK: - Symbols & Status

        EmojiPhraseMapping(emoji: "✅", phrases: [
            "check", "done", "complete", "yes", "correct", "verified", "approved"
        ]),
        EmojiPhraseMapping(emoji: "❌", phrases: [
            "x", "no", "wrong", "cross", "delete", "cancel", "reject"
        ]),
        EmojiPhraseMapping(emoji: "⭐", phrases: [
            "star", "favorite", "rating", "important"
        ]),
        EmojiPhraseMapping(emoji: "🌟", phrases: [
            "glowing star", "sparkle star", "shining"
        ]),
        EmojiPhraseMapping(emoji: "💯", phrases: [
            "hundred", "perfect", "100", "keep it real", "totally"
        ]),
        EmojiPhraseMapping(emoji: "🔥", phrases: [
            "fire", "hot", "lit", "awesome", "flame", "trending", "on fire"
        ]),
        EmojiPhraseMapping(emoji: "✨", phrases: [
            "sparkles", "magic", "shiny", "special", "fancy", "new"
        ]),
        EmojiPhraseMapping(emoji: "💥", phrases: [
            "explosion", "boom", "bang", "impact", "collision"
        ]),
        EmojiPhraseMapping(emoji: "⚡", phrases: [
            "lightning", "electric", "fast", "power", "energy", "zap"
        ]),
        EmojiPhraseMapping(emoji: "🎉", phrases: [
            "party", "celebration", "congrats", "yay", "celebrate", "confetti"
        ]),
        EmojiPhraseMapping(emoji: "🥳", phrases: [
            "party face", "celebrating", "birthday", "woohoo"
        ]),
        EmojiPhraseMapping(emoji: "🎊", phrases: [
            "confetti ball", "party", "celebration"
        ]),
        EmojiPhraseMapping(emoji: "🏆", phrases: [
            "trophy", "winner", "champion", "victory", "award", "first place"
        ]),
        EmojiPhraseMapping(emoji: "🥇", phrases: [
            "gold medal", "first place", "winner", "gold"
        ]),
        EmojiPhraseMapping(emoji: "🎯", phrases: [
            "target", "bullseye", "goal", "aim", "direct hit", "on point"
        ]),
        EmojiPhraseMapping(emoji: "💡", phrases: [
            "idea", "lightbulb", "bright idea", "thought", "eureka"
        ]),
        EmojiPhraseMapping(emoji: "⚠️", phrases: [
            "warning", "caution", "alert", "attention", "danger"
        ]),
        EmojiPhraseMapping(emoji: "🚫", phrases: [
            "no", "prohibited", "forbidden", "not allowed", "stop"
        ]),
        EmojiPhraseMapping(emoji: "❓", phrases: [
            "what", "huh", "why"
        ]),
        EmojiPhraseMapping(emoji: "❗", phrases: [
            "exclamation", "important", "attention", "alert"
        ]),
        EmojiPhraseMapping(emoji: "💤", phrases: [
            "zzz", "sleep", "sleeping", "tired", "snoring"
        ]),
        EmojiPhraseMapping(emoji: "💬", phrases: [
            "speech bubble", "comment", "message", "talking", "chat"
        ]),
        EmojiPhraseMapping(emoji: "💭", phrases: [
            "thought bubble", "thinking", "thought"
        ]),
        EmojiPhraseMapping(emoji: "👀", phrases: [
            "eyes", "looking", "watching", "see", "staring", "peek"
        ]),
        EmojiPhraseMapping(emoji: "👁️", phrases: [
            "eye", "single eye", "watching"
        ]),

        // MARK: - Nature & Weather

        EmojiPhraseMapping(emoji: "☀️", phrases: [
            "sun", "sunny", "sunshine", "bright", "summer"
        ]),
        EmojiPhraseMapping(emoji: "🌙", phrases: [
            "moon", "night", "crescent", "evening"
        ]),
        EmojiPhraseMapping(emoji: "⭐", phrases: [
            "star", "night", "twinkle"
        ]),
        EmojiPhraseMapping(emoji: "🌈", phrases: [
            "rainbow", "colorful", "pride", "colors"
        ]),
        EmojiPhraseMapping(emoji: "☁️", phrases: [
            "cloud", "cloudy", "overcast"
        ]),
        EmojiPhraseMapping(emoji: "🌧️", phrases: [
            "rain", "rainy", "raining"
        ]),
        EmojiPhraseMapping(emoji: "❄️", phrases: [
            "snow", "snowflake", "cold", "winter", "frozen"
        ]),
        EmojiPhraseMapping(emoji: "🌊", phrases: [
            "wave", "ocean", "sea", "water", "beach"
        ]),
        EmojiPhraseMapping(emoji: "🌸", phrases: [
            "cherry blossom", "flower", "spring", "pink flower"
        ]),
        EmojiPhraseMapping(emoji: "🌺", phrases: [
            "hibiscus", "flower", "tropical"
        ]),
        EmojiPhraseMapping(emoji: "🌹", phrases: [
            "rose", "red rose", "romance", "flower"
        ]),
        EmojiPhraseMapping(emoji: "🌻", phrases: [
            "sunflower", "flower", "yellow flower"
        ]),
        EmojiPhraseMapping(emoji: "🍀", phrases: [
            "four leaf clover", "lucky", "luck", "clover"
        ]),
        EmojiPhraseMapping(emoji: "🌲", phrases: [
            "tree", "evergreen", "christmas tree", "pine"
        ]),
        EmojiPhraseMapping(emoji: "🌴", phrases: [
            "palm tree", "tropical", "beach", "vacation"
        ]),

        // MARK: - Animals

        EmojiPhraseMapping(emoji: "🐶", phrases: [
            "dog", "puppy", "doggy", "pup", "cute dog"
        ]),
        EmojiPhraseMapping(emoji: "🐱", phrases: [
            "cat", "kitty", "kitten", "cute cat"
        ]),
        EmojiPhraseMapping(emoji: "🐻", phrases: [
            "bear", "teddy bear", "teddy"
        ]),
        EmojiPhraseMapping(emoji: "🦊", phrases: [
            "fox", "foxy"
        ]),
        EmojiPhraseMapping(emoji: "🦁", phrases: [
            "lion", "king", "brave"
        ]),
        EmojiPhraseMapping(emoji: "🐯", phrases: [
            "tiger", "fierce"
        ]),
        EmojiPhraseMapping(emoji: "🦄", phrases: [
            "unicorn", "magical", "fantasy"
        ]),
        EmojiPhraseMapping(emoji: "🐸", phrases: [
            "frog", "kermit", "ribbit"
        ]),
        EmojiPhraseMapping(emoji: "🐵", phrases: [
            "monkey", "ape", "chimp"
        ]),
        EmojiPhraseMapping(emoji: "🙈", phrases: [
            "see no evil", "covering eyes", "embarrassed", "can't look"
        ]),
        EmojiPhraseMapping(emoji: "🙉", phrases: [
            "hear no evil", "covering ears", "not listening"
        ]),
        EmojiPhraseMapping(emoji: "🙊", phrases: [
            "speak no evil", "covering mouth", "oops", "secret"
        ]),
        EmojiPhraseMapping(emoji: "🐔", phrases: [
            "chicken", "hen"
        ]),
        EmojiPhraseMapping(emoji: "🦆", phrases: [
            "duck", "quack"
        ]),
        EmojiPhraseMapping(emoji: "🐷", phrases: [
            "pig", "piggy"
        ]),
        EmojiPhraseMapping(emoji: "🐮", phrases: [
            "cow", "moo"
        ]),
        EmojiPhraseMapping(emoji: "🐴", phrases: [
            "horse", "pony"
        ]),
        EmojiPhraseMapping(emoji: "🦋", phrases: [
            "butterfly", "beautiful", "metamorphosis"
        ]),
        EmojiPhraseMapping(emoji: "🐝", phrases: [
            "bee", "busy bee", "buzz"
        ]),
        EmojiPhraseMapping(emoji: "🐛", phrases: [
            "bug", "caterpillar", "worm"
        ]),
        EmojiPhraseMapping(emoji: "🦀", phrases: [
            "crab", "cancer"
        ]),
        EmojiPhraseMapping(emoji: "🐙", phrases: [
            "octopus", "tentacles"
        ]),
        EmojiPhraseMapping(emoji: "🦈", phrases: [
            "shark", "jaws"
        ]),
        EmojiPhraseMapping(emoji: "🐬", phrases: [
            "dolphin", "flipper"
        ]),
        EmojiPhraseMapping(emoji: "🐳", phrases: [
            "whale", "spouting whale"
        ]),
        EmojiPhraseMapping(emoji: "🦅", phrases: [
            "eagle", "bird", "freedom"
        ]),
        EmojiPhraseMapping(emoji: "🦉", phrases: [
            "owl", "wise", "night bird"
        ]),
        EmojiPhraseMapping(emoji: "🐍", phrases: [
            "snake", "serpent", "hiss"
        ]),
        EmojiPhraseMapping(emoji: "🐢", phrases: [
            "turtle", "slow", "tortoise"
        ]),

        // MARK: - Food & Drink

        EmojiPhraseMapping(emoji: "🍕", phrases: [
            "pizza", "slice"
        ]),
        EmojiPhraseMapping(emoji: "🍔", phrases: [
            "burger", "hamburger", "cheeseburger"
        ]),
        EmojiPhraseMapping(emoji: "🍟", phrases: [
            "fries", "french fries"
        ]),
        EmojiPhraseMapping(emoji: "🌮", phrases: [
            "taco", "mexican"
        ]),
        EmojiPhraseMapping(emoji: "🌯", phrases: [
            "burrito", "wrap"
        ]),
        EmojiPhraseMapping(emoji: "🍣", phrases: [
            "sushi", "japanese food"
        ]),
        EmojiPhraseMapping(emoji: "🍜", phrases: [
            "noodles", "ramen", "pho"
        ]),
        EmojiPhraseMapping(emoji: "🍦", phrases: [
            "ice cream", "soft serve", "dessert"
        ]),
        EmojiPhraseMapping(emoji: "🍩", phrases: [
            "donut", "doughnut"
        ]),
        EmojiPhraseMapping(emoji: "🍪", phrases: [
            "cookie", "biscuit"
        ]),
        EmojiPhraseMapping(emoji: "🎂", phrases: [
            "birthday cake", "cake", "birthday"
        ]),
        EmojiPhraseMapping(emoji: "🍰", phrases: [
            "cake slice", "dessert", "cake"
        ]),
        EmojiPhraseMapping(emoji: "☕", phrases: [
            "coffee", "tea", "hot drink", "cafe"
        ]),
        EmojiPhraseMapping(emoji: "🍺", phrases: [
            "beer", "drink", "cheers"
        ]),
        EmojiPhraseMapping(emoji: "🍷", phrases: [
            "wine", "red wine", "drink"
        ]),
        EmojiPhraseMapping(emoji: "🥂", phrases: [
            "champagne", "cheers", "toast", "celebrate"
        ]),
        EmojiPhraseMapping(emoji: "🍎", phrases: [
            "apple", "red apple", "fruit"
        ]),
        EmojiPhraseMapping(emoji: "🍌", phrases: [
            "banana", "fruit"
        ]),
        EmojiPhraseMapping(emoji: "🍇", phrases: [
            "grapes", "fruit"
        ]),
        EmojiPhraseMapping(emoji: "🍓", phrases: [
            "strawberry", "berry", "fruit"
        ]),
        EmojiPhraseMapping(emoji: "🥑", phrases: [
            "avocado", "guac"
        ]),
        EmojiPhraseMapping(emoji: "🥕", phrases: [
            "carrot", "vegetable"
        ]),
        EmojiPhraseMapping(emoji: "🌶️", phrases: [
            "hot pepper", "spicy", "chili"
        ]),
        EmojiPhraseMapping(emoji: "🧀", phrases: [
            "cheese"
        ]),

        // MARK: - Activities & Objects

        EmojiPhraseMapping(emoji: "⚽", phrases: [
            "soccer", "football", "ball"
        ]),
        EmojiPhraseMapping(emoji: "🏀", phrases: [
            "basketball", "ball", "hoops"
        ]),
        EmojiPhraseMapping(emoji: "🎮", phrases: [
            "gaming", "video game", "controller", "play"
        ]),
        EmojiPhraseMapping(emoji: "🎬", phrases: [
            "movie", "film", "cinema", "action"
        ]),
        EmojiPhraseMapping(emoji: "🎵", phrases: [
            "music", "note", "song", "tune"
        ]),
        EmojiPhraseMapping(emoji: "🎸", phrases: [
            "guitar", "rock", "music"
        ]),
        EmojiPhraseMapping(emoji: "🎤", phrases: [
            "microphone", "singing", "karaoke", "mic"
        ]),
        EmojiPhraseMapping(emoji: "📱", phrases: [
            "phone", "mobile", "cell phone", "smartphone"
        ]),
        EmojiPhraseMapping(emoji: "💻", phrases: [
            "laptop", "computer", "work"
        ]),
        EmojiPhraseMapping(emoji: "📸", phrases: [
            "camera", "photo", "picture", "photography"
        ]),
        EmojiPhraseMapping(emoji: "🔑", phrases: [
            "key", "unlock", "password"
        ]),
        EmojiPhraseMapping(emoji: "💰", phrases: [
            "money", "cash", "rich", "money bag"
        ]),
        EmojiPhraseMapping(emoji: "💵", phrases: [
            "dollar", "money", "cash"
        ]),
        EmojiPhraseMapping(emoji: "💎", phrases: [
            "diamond", "gem", "precious", "jewel"
        ]),
        EmojiPhraseMapping(emoji: "🎁", phrases: [
            "gift", "present", "birthday"
        ]),
        EmojiPhraseMapping(emoji: "📦", phrases: [
            "package", "box", "delivery"
        ]),
        EmojiPhraseMapping(emoji: "✈️", phrases: [
            "airplane", "flight", "travel", "plane"
        ]),
        EmojiPhraseMapping(emoji: "🚗", phrases: [
            "car", "drive", "automobile"
        ]),
        EmojiPhraseMapping(emoji: "🏠", phrases: [
            "house", "home"
        ]),
        EmojiPhraseMapping(emoji: "⏰", phrases: [
            "alarm", "clock", "time", "wake up"
        ]),
        EmojiPhraseMapping(emoji: "📅", phrases: [
            "calendar", "date", "schedule", "event"
        ]),
        EmojiPhraseMapping(emoji: "📝", phrases: [
            "memo", "note", "write", "document"
        ]),
        EmojiPhraseMapping(emoji: "✏️", phrases: [
            "pencil", "write", "edit"
        ]),
        EmojiPhraseMapping(emoji: "📚", phrases: [
            "books", "reading", "study", "library"
        ]),
        EmojiPhraseMapping(emoji: "🔒", phrases: [
            "lock", "locked", "secure", "private"
        ]),
        EmojiPhraseMapping(emoji: "🔓", phrases: [
            "unlock", "unlocked", "open"
        ]),
    ]
}

// MARK: - Emoji Category

/// Categories for emoji grouping
public enum EmojiCategory: String, CaseIterable {
    case faces = "faces"
    case hearts = "hearts"
    case gestures = "gestures"
    case symbols = "symbols"
    case nature = "nature"
    case animals = "animals"
    case food = "food"
    case activities = "activities"

    /// Alternative names that trigger this category
    var triggerPhrases: [String] {
        switch self {
        case .faces: return ["faces", "face", "emotions", "emotion", "expressions", "smiley", "smileys", "emoji faces"]
        case .hearts: return ["hearts", "heart", "love", "loving", "romance", "romantic"]
        case .gestures: return ["gestures", "gesture", "hands", "hand", "fingers", "pointing"]
        case .symbols: return ["symbols", "symbol", "icons", "status", "signs"]
        case .nature: return ["nature", "weather", "plants", "flowers", "flower", "trees", "sky", "outdoors"]
        case .animals: return ["animals", "animal", "pets", "pet", "creatures", "wildlife", "zoo"]
        case .food: return ["food", "foods", "eating", "drinks", "drink", "hungry", "snacks", "dessert", "meal"]
        case .activities: return ["activities", "activity", "sports", "games", "gaming", "objects", "things", "stuff", "travel"]
        }
    }

    /// Display name for the category
    public var displayName: String {
        switch self {
        case .faces: return "Faces"
        case .hearts: return "Hearts"
        case .gestures: return "Gestures"
        case .symbols: return "Symbols"
        case .nature: return "Nature"
        case .animals: return "Animals"
        case .food: return "Food"
        case .activities: return "Activities"
        }
    }
}

// MARK: - Emoji Recognizer

/// Recognizes emojis from voice input using NLEmbedding semantic similarity
public final class EmojiRecognizer: @unchecked Sendable {
    public static let shared = EmojiRecognizer()

    /// Minimum confidence threshold for emoji matching
    public let confidenceThreshold: Float = 0.5

    /// Pre-computed embeddings for all emoji phrases
    private let phraseEmbeddings: [(emoji: String, phrase: String, embedding: [Double])]

    /// NLEmbedding for English
    private let embedding: NLEmbedding?

    /// Quick lookup map for exact matches
    private let exactMatchMap: [String: String]

    /// Category to emojis mapping
    private let categoryEmojis: [EmojiCategory: [String]]

    /// Phrase to category mapping for quick lookup
    private let categoryTriggerMap: [String: EmojiCategory]

    private init() {
        // Load English word embedding
        embedding = NLEmbedding.wordEmbedding(for: .english)

        // Pre-compute embeddings for all phrases
        var embeddings: [(String, String, [Double])] = []
        var exactMap: [String: String] = [:]

        if let emb = embedding {
            for mapping in EmojiPhraseMapping.all {
                for phrase in mapping.phrases {
                    // Add to exact match map
                    exactMap[phrase.lowercased()] = mapping.emoji

                    // Compute embedding
                    if let vector = Self.computeSentenceEmbedding(phrase, using: emb) {
                        embeddings.append((mapping.emoji, phrase, vector))
                    }
                }
            }
        }

        phraseEmbeddings = embeddings
        exactMatchMap = exactMap

        // Build category mappings
        var catEmojis: [EmojiCategory: [String]] = [:]
        for mapping in EmojiPhraseMapping.all {
            let category = EmojiPhraseMapping.category(for: mapping.emoji)
            if catEmojis[category] == nil {
                catEmojis[category] = []
            }
            if !catEmojis[category]!.contains(mapping.emoji) {
                catEmojis[category]!.append(mapping.emoji)
            }
        }
        categoryEmojis = catEmojis

        // Build category trigger phrase map
        var triggerMap: [String: EmojiCategory] = [:]
        for category in EmojiCategory.allCases {
            for phrase in category.triggerPhrases {
                triggerMap[phrase.lowercased()] = category
            }
        }
        categoryTriggerMap = triggerMap
    }

    // MARK: - Public API

    /// Check if the text is a category name and return the category
    public func matchCategory(_ text: String) -> EmojiCategory? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return categoryTriggerMap[normalized]
    }

    /// Get all emojis for a category
    public func emojis(for category: EmojiCategory) -> [String] {
        return categoryEmojis[category] ?? []
    }

    /// Get emojis for a category as match tuples (for UI consistency)
    public func categoryMatches(for category: EmojiCategory) -> [(emoji: String, confidence: Float)] {
        return emojis(for: category).map { ($0, 1.0) }
    }

    /// Recognize emoji from transcribed voice input
    /// - Parameter text: The transcribed text (e.g., "heart", "thumbs up", "laughing crying")
    /// - Returns: Tuple of (emoji, confidence) or nil if no match found
    public func recognize(_ text: String) -> (emoji: String, confidence: Float)? {
        let normalizedText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedText.isEmpty else { return nil }

        // First try exact match
        if let exactEmoji = exactMatchMap[normalizedText] {
            return (exactEmoji, 1.0)
        }

        // Try partial exact match (text contains a phrase)
        for (phrase, emoji) in exactMatchMap {
            if normalizedText.contains(phrase) && phrase.count >= 3 {
                return (emoji, 0.95)
            }
        }

        // Fall back to semantic similarity
        guard let emb = embedding,
              let inputVector = Self.computeSentenceEmbedding(normalizedText, using: emb) else {
            return nil
        }

        var bestMatch: (emoji: String, phrase: String, similarity: Float) = ("", "", 0)

        for (emoji, phrase, phraseVector) in phraseEmbeddings {
            let similarity = Self.cosineSimilarity(inputVector, phraseVector)
            if similarity > bestMatch.similarity {
                bestMatch = (emoji, phrase, similarity)
            }
        }

        guard bestMatch.similarity >= confidenceThreshold else { return nil }

        return (bestMatch.emoji, bestMatch.similarity)
    }

    /// Get top N emoji matches for voice input
    /// - Parameters:
    ///   - text: The transcribed text
    ///   - limit: Maximum number of results (default 5)
    /// - Returns: Array of (emoji, confidence) sorted by confidence descending
    public func topMatches(_ text: String, limit: Int = 5) -> [(emoji: String, confidence: Float)] {
        let normalizedText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedText.isEmpty else { return [] }

        // Check if this is a category request first (e.g., "food", "animals")
        if let category = matchCategory(normalizedText) {
            return categoryMatches(for: category).prefix(limit).map { $0 }
        }

        var matches: [(emoji: String, similarity: Float)] = []
        var seenEmojis: Set<String> = []

        // ALWAYS check exact matches first - highest priority
        if let exactEmoji = exactMatchMap[normalizedText] {
            matches.append((exactEmoji, 1.0))
            seenEmojis.insert(exactEmoji)
        }

        // Also check partial exact matches (text contains a known phrase)
        for (phrase, emoji) in exactMatchMap {
            guard !seenEmojis.contains(emoji) else { continue }
            if normalizedText.contains(phrase) && phrase.count >= 3 {
                matches.append((emoji, 0.95))
                seenEmojis.insert(emoji)
            }
        }

        // Then try semantic similarity if embedding is available
        if let emb = embedding,
           let inputVector = Self.computeSentenceEmbedding(normalizedText, using: emb) {

            for (emoji, _, phraseVector) in phraseEmbeddings {
                // Skip duplicates (already found via exact match)
                guard !seenEmojis.contains(emoji) else { continue }

                let similarity = Self.cosineSimilarity(inputVector, phraseVector)
                if similarity >= confidenceThreshold {
                    matches.append((emoji, similarity))
                    seenEmojis.insert(emoji)
                }
            }
        }

        // Sort by similarity and take top N
        return matches
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .map { ($0.emoji, $0.similarity) }
    }

    // MARK: - Embedding Computation

    /// Compute sentence embedding by averaging word embeddings
    private static func computeSentenceEmbedding(_ text: String, using embedding: NLEmbedding) -> [Double]? {
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

        // Average the vectors
        return sum.map { $0 / Double(wordCount) }
    }

    /// Compute cosine similarity between two vectors
    private static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Double = 0
        var normA: Double = 0
        var normB: Double = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return Float(dotProduct / denominator)
    }
}

// MARK: - Recent Emojis

/// Tracks recently used emojis for quick access
public final class RecentEmojis {
    public static let shared = RecentEmojis()

    private let maxRecent = 16
    private let key = "recentEmojis"
    private let defaults: UserDefaults

    private init() {
        // Use app group for keyboard extension access
        if let groupDefaults = UserDefaults(suiteName: kTalkieAppGroup) {
            defaults = groupDefaults
        } else {
            defaults = .standard
        }
    }

    /// Get recent emojis, most recent first
    public var all: [String] {
        return defaults.stringArray(forKey: key) ?? []
    }

    /// Add an emoji to recents (moves to front if already present)
    public func add(_ emoji: String) {
        var recents = all
        // Remove if already present
        recents.removeAll { $0 == emoji }
        // Add to front
        recents.insert(emoji, at: 0)
        // Trim to max
        if recents.count > maxRecent {
            recents = Array(recents.prefix(maxRecent))
        }
        defaults.set(recents, forKey: key)
    }

    /// Get recent emojis as match tuples (for UI consistency)
    public func recentMatches(limit: Int = 8) -> [(emoji: String, confidence: Float)] {
        return all.prefix(limit).map { ($0, 1.0) }
    }

    /// Clear all recent emojis
    public func clear() {
        defaults.removeObject(forKey: key)
    }
}
