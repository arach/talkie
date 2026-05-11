/**
 * Milestones App - background.js
 *
 * Celebrates voice capture achievements with milestone notifications.
 * Uses Chrome extension-style APIs provided by Talkie.
 */

(function() {
    'use strict';

    // ============================================================
    // Milestone Definitions
    // ============================================================

    const MILESTONES = {
        // Memo count milestones
        memos: [
            { id: 'first-memo', count: 1, title: 'First Capture!', subtitle: 'You created your first memo', icon: 'star.fill' },
            { id: 'memos-10', count: 10, title: '10 Memos!', subtitle: 'You\'re getting the hang of it', icon: 'flame.fill' },
            { id: 'memos-50', count: 50, title: '50 Memos!', subtitle: 'Voice capture pro', icon: 'medal.fill' },
            { id: 'memos-100', count: 100, title: '100 Memos!', subtitle: 'Century club member', icon: 'trophy.fill' },
            { id: 'memos-500', count: 500, title: '500 Memos!', subtitle: 'Prolific voice capturer', icon: 'crown.fill' },
            { id: 'memos-1000', count: 1000, title: '1000 Memos!', subtitle: 'Voice capture legend', icon: 'sparkles' }
        ],

        // Dictation count milestones
        dictations: [
            { id: 'first-dictation', count: 1, title: 'First Dictation!', subtitle: 'Live voice-to-text', icon: 'waveform' },
            { id: 'dictations-25', count: 25, title: '25 Dictations!', subtitle: 'Hands-free champion', icon: 'keyboard.fill' },
            { id: 'dictations-100', count: 100, title: '100 Dictations!', subtitle: 'Dictation master', icon: 'star.circle.fill' }
        ],

        // Word count milestones
        words: [
            { id: 'words-1000', count: 1000, title: '1,000 Words!', subtitle: 'Your voice, captured', icon: 'text.word.spacing' },
            { id: 'words-10000', count: 10000, title: '10,000 Words!', subtitle: 'A small novel', icon: 'book.fill' },
            { id: 'words-50000', count: 50000, title: '50,000 Words!', subtitle: 'NaNoWriMo complete!', icon: 'books.vertical.fill' },
            { id: 'words-100000', count: 100000, title: '100,000 Words!', subtitle: 'Voice author extraordinaire', icon: 'laurel.leading' }
        ],

        // Session milestones
        sessions: [
            { id: 'sessions-7', count: 7, title: '7 Day Streak!', subtitle: 'One week of voice capture', icon: 'calendar' },
            { id: 'sessions-30', count: 30, title: '30 Sessions!', subtitle: 'A month of momentum', icon: 'calendar.badge.checkmark' },
            { id: 'sessions-100', count: 100, title: '100 Sessions!', subtitle: 'Consistency champion', icon: 'star.leadinghalf.filled' }
        ],

        // Polish/AI milestones
        polish: [
            { id: 'first-polish', count: 1, title: 'First Polish!', subtitle: 'AI-enhanced writing', icon: 'sparkles' },
            { id: 'polish-25', count: 25, title: '25 Polishes!', subtitle: 'AI collaboration pro', icon: 'wand.and.stars' }
        ]
    };

    // ============================================================
    // State
    // ============================================================

    let completedMilestones = new Set();

    // ============================================================
    // Storage
    // ============================================================

    function loadCompletedMilestones(callback) {
        talkie.storage.local.get(['completedMilestones'], (result) => {
            if (result.completedMilestones && Array.isArray(result.completedMilestones)) {
                completedMilestones = new Set(result.completedMilestones);
            }
            if (callback) callback();
        });
    }

    function saveCompletedMilestones() {
        talkie.storage.local.set({
            completedMilestones: Array.from(completedMilestones)
        });
    }

    // ============================================================
    // Milestone Checking
    // ============================================================

    function checkMilestones(category, currentCount) {
        const milestones = MILESTONES[category] || [];

        for (const milestone of milestones) {
            if (currentCount >= milestone.count && !completedMilestones.has(milestone.id)) {
                celebrate(milestone);
            }
        }
    }

    function celebrate(milestone) {
        completedMilestones.add(milestone.id);
        saveCompletedMilestones();

        talkie.notifications.create(milestone.id, {
            title: milestone.title,
            message: milestone.subtitle,
            iconUrl: milestone.icon
        });

        console.log('[Milestones] Celebrated:', milestone.id);
    }

    // ============================================================
    // Sync with Current State
    // ============================================================

    function syncWithCurrentState() {
        talkie.state.get(['memoCount', 'dictationCount', 'totalWords', 'sessionCount', 'polishCount'], (state) => {
            // Check all categories against current counts
            // This catches up on any milestones earned while app wasn't loaded
            checkMilestones('memos', state.memoCount || 0);
            checkMilestones('dictations', state.dictationCount || 0);
            checkMilestones('words', state.totalWords || 0);
            checkMilestones('sessions', state.sessionCount || 0);
            checkMilestones('polish', state.polishCount || 0);

            console.log('[Milestones] Synced with state:', state);
        });
    }

    // ============================================================
    // Event Listeners
    // ============================================================

    talkie.events.onMemoCreated.addListener((data) => {
        console.log('[Milestones] Memo created:', data);
        checkMilestones('memos', data.memoCount || 0);
        checkMilestones('words', data.totalWords || 0);
    });

    talkie.events.onDictationCompleted.addListener((data) => {
        console.log('[Milestones] Dictation completed:', data);
        checkMilestones('dictations', data.dictationCount || 0);
    });

    talkie.events.onPolishCompleted.addListener((data) => {
        console.log('[Milestones] Polish completed:', data);
        checkMilestones('polish', data.polishCount || 0);
    });

    talkie.events.onSessionStarted.addListener((data) => {
        console.log('[Milestones] Session started:', data);
        checkMilestones('sessions', data.sessionNumber || 0);
    });

    // ============================================================
    // Initialize
    // ============================================================

    loadCompletedMilestones(() => {
        syncWithCurrentState();
        console.log('[Milestones] Initialized with', completedMilestones.size, 'completed milestones');
    });

})();
