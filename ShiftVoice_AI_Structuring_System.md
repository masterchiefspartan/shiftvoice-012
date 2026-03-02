# ShiftVoice — AI Structuring System
## Making Voice-to-Action-Items Bulletproof

---

## The Problem

The entire product depends on one pipeline:

```
Voice → Transcript → Structured Items → Action Items
```

If any step is unreliable, users won't trust the product. A shift lead who records "the fryer is down, we're out of salmon, and Sarah needs to train the new host" MUST get 3 items back, correctly categorized, with sensible action items. Not 2. Not 4. Not 3 items where one is about something they never said.

This document defines the complete system: the prompt architecture, validation layer, confidence scoring, fallback logic, and the feedback loop that improves accuracy over time.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────┐
│                 VOICE INPUT                       │
│          (AVFoundation recording)                 │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│            STEP 1: TRANSCRIPTION                  │
│         (Apple Speech Framework)                  │
│                                                   │
│  Input:  Audio file                               │
│  Output: Raw transcript text                      │
│  Runs:   On-device, no network needed             │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│          STEP 2: TRANSCRIPT CLEANING              │
│            (Local preprocessing)                  │
│                                                   │
│  - Remove filler words (um, uh, like, you know)   │
│  - Normalize punctuation                          │
│  - Flag low-confidence transcript segments        │
│  Runs: On-device, instant                         │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│          STEP 3: AI STRUCTURING                   │
│          (OpenAI API — GPT-4o-mini)               │
│                                                   │
│  Input:  Cleaned transcript + industry context     │
│  Output: JSON array of structured items            │
│  Runs:   Requires network                          │
│                                                   │
│  ┌─────────────────────────────────────────────┐  │
│  │  PROMPT = System Prompt + Industry Context   │  │
│  │         + Transcript + Output Schema         │  │
│  └─────────────────────────────────────────────┘  │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│          STEP 4: VALIDATION LAYER                 │
│            (Local post-processing)                │
│                                                   │
│  - Parse JSON response                            │
│  - Validate each item against transcript          │
│  - Score confidence per item                      │
│  - Flag items that may be hallucinated            │
│  - Flag if item count seems wrong                 │
│  Runs: On-device, instant                         │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│          STEP 5: USER REVIEW                      │
│            (Review screen)                        │
│                                                   │
│  - Show structured items with confidence flags    │
│  - "Did we get this right?" on low-confidence     │
│  - User edits = training signal for improvement   │
└──────────────────────────────────────────────────┘
```

---

## Step 1: Transcription

Apple's Speech framework handles this. The main improvements you can make:

```swift
// Use on-device recognition for speed and privacy
let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
let request = SFSpeechURLRecognitionRequest(url: audioFileURL)

// CRITICAL: Request these for better downstream structuring
request.shouldReportPartialResults = false  // Wait for final result
request.taskHint = .dictation               // Optimize for natural speech, not commands
// If available on device (iOS 16+):
request.requiresOnDeviceRecognition = false  // Allow server-side for accuracy
// Set to true for offline, but accuracy drops ~10-15%

// Capture per-segment confidence
recognizer.recognitionTask(with: request) { result, error in
    if let result = result, result.isFinal {
        let transcript = result.bestTranscription.formattedString
        
        // Capture segment-level confidence for later use
        let segments = result.bestTranscription.segments.map { segment in
            TranscriptSegment(
                text: segment.substring,
                confidence: segment.confidence,
                timestamp: segment.timestamp,
                duration: segment.duration
            )
        }
        
        // Flag low-confidence segments
        let lowConfidenceSegments = segments.filter { $0.confidence < 0.5 }
    }
}
```

**Key improvement:** Capture per-segment confidence scores. If a section of the transcript has low confidence (speech was unclear, background noise), pass that signal to the AI structuring step so it knows to be cautious about that section.

---

## Step 2: Transcript Cleaning

Before sending to the AI, clean the transcript. This significantly improves structuring accuracy because filler words confuse topic boundary detection.

```swift
func cleanTranscript(_ raw: String) -> CleanedTranscript {
    var text = raw
    
    // Remove filler words (preserve meaning, reduce noise)
    let fillers = [
        "um", "uh", "uh huh", "hmm", "like",
        "you know", "I mean", "basically", "literally",
        "sort of", "kind of", "I guess", "right",
        "so yeah", "anyway", "anyhow"
    ]
    for filler in fillers {
        // Only remove when they're standalone filler, not part of meaning
        // "I mean the fryer" → "the fryer" (filler)
        // "I mean what I said" → keep (meaningful)
        text = text.replacingOccurrences(
            of: "\\b\(filler)\\b\\s*,?\\s*",
            with: " ",
            options: .regularExpression
        )
    }
    
    // Normalize whitespace
    text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    
    // Detect topic boundaries (transition phrases)
    let transitions = [
        "also", "and also", "another thing", "oh and",
        "one more thing", "besides that", "on top of that",
        "separately", "different topic", "other than that",
        "plus", "and then", "the other thing is"
    ]
    
    // Count likely distinct topics (rough heuristic)
    var topicSignals = 1  // At least 1 topic
    for transition in transitions {
        if text.lowercased().contains(transition) {
            topicSignals += 1
        }
    }
    
    return CleanedTranscript(
        text: text,
        estimatedTopicCount: min(topicSignals, 8),  // Cap at reasonable max
        originalText: raw
    )
}
```

---

## Step 3: AI Structuring Prompt — THE CRITICAL PIECE

This is where 90% of the reliability lives. The prompt has 4 parts:

1. **System prompt** — defines the role and rules
2. **Industry context** — injected from the industry config
3. **Transcript input** — the cleaned transcript
4. **Output schema** — exactly what JSON structure to return

### The Complete Prompt

```
SYSTEM PROMPT:
--------------
You are an AI assistant for ShiftVoice, an operations management tool for frontline teams. Your job is to take a voice transcript from a shift worker and extract every distinct operational item mentioned.

RULES — FOLLOW THESE EXACTLY:

1. NEVER MERGE: Each distinct topic, issue, or instruction in the transcript becomes its OWN separate item. If someone mentions a broken fryer AND a staffing issue, those are 2 items, not 1. When in doubt, SPLIT into separate items rather than combining.

2. NEVER DROP: Every operational topic mentioned in the transcript MUST appear in your output. Even brief or casual mentions ("oh and tell Sarah about Thursday") are separate items. If it's something the next shift needs to know, it's an item.

3. NEVER HALLUCINATE: Only extract information that is EXPLICITLY stated in the transcript. Do not infer issues that weren't mentioned. Do not add details that aren't in the transcript. If the speaker says "the fryer is making noise," the item is about noise — do not escalate it to "fryer is broken" unless they said that.

4. QUOTE, DON'T INTERPRET: The "content" field should closely reflect what the speaker actually said, rephrased for clarity but not embellished. Keep it factual and specific.

5. ACTION ITEMS MUST BE ACTIONABLE: Every action item should be a specific next step that someone can actually do. "Look into it" is not actionable. "Schedule repair tech to inspect fryer" is actionable. "Monitor the situation" is not actionable. "Check fryer temperature every 2 hours and log readings" is actionable.

6. CATEGORIZE CONSERVATIVELY: Only assign categories from the provided list. If an item doesn't clearly fit a category, use the most general applicable one.

7. URGENCY IS BASED ON OPERATIONAL IMPACT:
   - "urgent": Safety risk, equipment failure affecting operations, guest/client impact, compliance issue, or time-sensitive deadline within this shift
   - "normal": Needs attention within 24 hours, operational but not critical
   - "low": Informational, can wait, or is a reminder for a future date

OUTPUT FORMAT:
Return ONLY a valid JSON object with this exact structure. No markdown, no explanation, no preamble.

{
  "items": [
    {
      "content": "Clear, concise description of what was said",
      "category": "One of the provided category names",
      "urgency": "urgent" | "normal" | "low",
      "action_item": "Specific, actionable next step",
      "source_quote": "The exact words from the transcript that this item is based on"
    }
  ],
  "item_count": <number>,
  "transcript_coverage": "complete" | "partial",
  "notes": "Any concerns about transcript quality or ambiguous items"
}

The "source_quote" field is critical — it maps each item back to the exact words in the transcript. This is used for validation. Every item MUST have a source_quote that exists in the transcript.

The "transcript_coverage" field should be "complete" if you believe you captured everything, or "partial" if parts of the transcript were unclear or you're unsure if you caught everything.
```

```
INDUSTRY CONTEXT (injected per industry):
------------------------------------------
{config.ai.system_prompt_context}

AVAILABLE CATEGORIES (only use these):
{config.categories.defaults.map(c => c.name).join(", ")}

COMMON VOCABULARY FOR THIS INDUSTRY:
{config.ai.common_vocabulary.join(", ")}

CATEGORIZATION GUIDELINES:
{config.ai.categorization_hints.join("\n")}
```

```
USER MESSAGE:
-------------
Here is the voice transcript to structure. Extract every distinct operational item.

TRANSCRIPT:
"{cleanedTranscript.text}"

ESTIMATED TOPICS: The speaker appears to cover approximately {cleanedTranscript.estimatedTopicCount} distinct topics. Make sure you capture at least this many items, unless the estimate seems wrong based on your reading.

Return ONLY the JSON object. No other text.
```

### Why This Prompt Works Better Than What You Probably Have

**1. The "NEVER MERGE" rule is explicit and first.** Most structuring prompts say "extract items" without explicitly forbidding merging. The AI defaults to grouping related things together because that's what LLMs do — they summarize. You need to fight that instinct directly.

**2. The source_quote field creates accountability.** By requiring the AI to cite the exact words from the transcript, you force it to ground each item in what was actually said. This makes hallucination detectable — in the validation step, you can check whether the source_quote actually appears in the transcript.

**3. The estimated topic count is a check signal.** The local preprocessing already counted likely topic transitions. Passing that number to the AI as a hint ("the speaker appears to cover approximately 3 distinct topics") gives it a target to validate against. If the AI only returns 2 items but the estimate was 3, it's more likely to reconsider.

**4. The urgency definitions are operational, not abstract.** Instead of "high/medium/low," the urgency levels are tied to specific operational situations (safety risk, equipment failure, time-sensitive deadline). This dramatically reduces urgency misassignment.

**5. The action items have anti-patterns.** Telling the AI that "look into it" and "monitor the situation" are NOT acceptable pushes it toward specific, actionable outputs.

---

## Step 3B: Model Selection & API Call

```swift
func structureTranscript(
    cleanedTranscript: CleanedTranscript,
    industryConfig: IndustryConfig
) async throws -> StructuringResult {
    
    let systemPrompt = buildSystemPrompt()  // The system prompt above
    let industryContext = buildIndustryContext(industryConfig)  // Injected context
    let userMessage = buildUserMessage(cleanedTranscript)  // Transcript + topic estimate
    
    let requestBody: [String: Any] = [
        "model": "gpt-4o-mini",  // Fast, cheap, good enough for structuring
        // Use gpt-4o for complex multi-topic recordings if budget allows
        "messages": [
            ["role": "system", "content": systemPrompt + "\n\n" + industryContext],
            ["role": "user", "content": userMessage]
        ],
        "temperature": 0.1,      // LOW temperature = more deterministic, less creative
                                  // This is critical — you want consistency, not creativity
        "max_tokens": 2000,
        "response_format": ["type": "json_object"]  // Force JSON output
    ]
    
    // Timeout: 15 seconds, hard fail at 30
    let response = try await callOpenAI(requestBody, timeout: 15)
    
    return try parseStructuringResponse(response)
}
```

**Critical setting: temperature = 0.1.** Most developers leave this at the default (0.7-1.0), which introduces randomness. For structuring, you want the AI to give the same output every time for the same input. Low temperature makes the output deterministic and consistent. The same transcript should produce the same items every time.

**Model choice: gpt-4o-mini** is the right balance of speed, cost, and quality for this task. The structuring task is well-defined enough that you don't need the full gpt-4o. If you see accuracy issues on complex recordings (5+ topics), you can selectively upgrade to gpt-4o for those cases.

---

## Step 4: Validation Layer — CATCH FAILURES BEFORE THE USER SEES THEM

This runs locally after the AI returns its response. It checks for every known failure mode.

```swift
struct ValidationResult {
    let items: [StructuredItem]
    let confidence: Double           // 0.0 to 1.0 overall confidence
    let warnings: [ValidationWarning]
    let needsUserReview: Bool
}

enum ValidationWarning {
    case possibleMergedItems(reason: String)
    case possibleDroppedContent(missedText: String)
    case possibleHallucination(item: StructuredItem, reason: String)
    case lowTranscriptConfidence(segments: [String])
    case itemCountMismatch(expected: Int, got: Int)
    case missingSourceQuote(item: StructuredItem)
    case duplicateItems(indices: [Int])
}

func validateStructuringResult(
    result: StructuringResult,
    transcript: CleanedTranscript
) -> ValidationResult {
    
    var warnings: [ValidationWarning] = []
    var overallConfidence: Double = 1.0
    
    // ─── CHECK 1: Source Quote Verification ───
    // Every item's source_quote should exist (approximately) in the transcript
    for item in result.items {
        if let quote = item.sourceQuote {
            let similarity = fuzzyMatch(quote, in: transcript.text)
            if similarity < 0.6 {
                warnings.append(.possibleHallucination(
                    item: item,
                    reason: "Source quote '\(quote.prefix(50))...' not found in transcript"
                ))
                overallConfidence -= 0.2
            }
        } else {
            warnings.append(.missingSourceQuote(item: item))
            overallConfidence -= 0.1
        }
    }
    
    // ─── CHECK 2: Topic Count Match ───
    // Compare AI's item count against our local topic estimate
    let expectedTopics = transcript.estimatedTopicCount
    let actualItems = result.items.count
    
    if actualItems < expectedTopics - 1 {
        // AI returned fewer items than expected — possible drop or merge
        warnings.append(.itemCountMismatch(expected: expectedTopics, got: actualItems))
        overallConfidence -= 0.15
    }
    
    // ─── CHECK 3: Transcript Coverage ───
    // Check if significant portions of the transcript are unaccounted for
    var accountedText = ""
    for item in result.items {
        if let quote = item.sourceQuote {
            accountedText += quote + " "
        }
    }
    
    // Find transcript segments not covered by any source_quote
    let transcriptWords = Set(transcript.text.lowercased().split(separator: " ").map(String.init))
    let accountedWords = Set(accountedText.lowercased().split(separator: " ").map(String.init))
    let uncoveredWords = transcriptWords.subtracting(accountedWords)
    
    // Filter out common words to find meaningful uncovered content
    let stopWords = Set(["the", "a", "an", "is", "was", "are", "and", "or", "but",
                         "in", "on", "at", "to", "for", "of", "with", "that", "this",
                         "it", "so", "we", "i", "they", "he", "she", "about", "just",
                         "its", "also", "been", "have", "has", "had", "do", "does",
                         "did", "will", "would", "could", "should", "may", "might"])
    let meaningfulUncovered = uncoveredWords.subtracting(stopWords)
    
    let coverageRatio = 1.0 - (Double(meaningfulUncovered.count) / Double(max(transcriptWords.subtracting(stopWords).count, 1)))
    
    if coverageRatio < 0.7 {
        let missedContent = meaningfulUncovered.joined(separator: ", ")
        warnings.append(.possibleDroppedContent(missedText: missedContent))
        overallConfidence -= 0.2
    }
    
    // ─── CHECK 4: Duplicate Detection ───
    // Check if two items are suspiciously similar (possible over-splitting)
    for i in 0..<result.items.count {
        for j in (i+1)..<result.items.count {
            let similarity = cosineSimilarity(result.items[i].content, result.items[j].content)
            if similarity > 0.8 {
                warnings.append(.duplicateItems(indices: [i, j]))
                overallConfidence -= 0.1
            }
        }
    }
    
    // ─── CHECK 5: Long Items (Possible Merges) ───
    // If any single item's content is unusually long, it may contain merged topics
    for item in result.items {
        let wordCount = item.content.split(separator: " ").count
        if wordCount > 30 {
            warnings.append(.possibleMergedItems(
                reason: "Item '\(item.content.prefix(50))...' is unusually long (\(wordCount) words) — may contain multiple topics"
            ))
            overallConfidence -= 0.1
        }
    }
    
    // ─── CHECK 6: AI Self-Reported Coverage ───
    if result.transcriptCoverage == "partial" {
        overallConfidence -= 0.15
    }
    
    // Cap confidence between 0 and 1
    overallConfidence = max(0.0, min(1.0, overallConfidence))
    
    let needsReview = overallConfidence < 0.7 || !warnings.isEmpty
    
    return ValidationResult(
        items: result.items,
        confidence: overallConfidence,
        warnings: warnings,
        needsUserReview: needsReview
    )
}

// Fuzzy matching helper — checks if a quote approximately exists in the transcript
func fuzzyMatch(_ quote: String, in text: String) -> Double {
    let quoteWords = quote.lowercased().split(separator: " ").map(String.init)
    let textWords = text.lowercased().split(separator: " ").map(String.init)
    
    var matchedWords = 0
    for word in quoteWords {
        if textWords.contains(word) {
            matchedWords += 1
        }
    }
    
    return Double(matchedWords) / Double(max(quoteWords.count, 1))
}
```

---

## Step 5: Fallback Strategy — WHEN THE AI FAILS

The AI WILL fail sometimes. Network timeout, bad JSON, hallucinated garbage. You need a local fallback that produces reasonable results without any API call.

```swift
func localFallbackStructuring(transcript: CleanedTranscript, industryConfig: IndustryConfig) -> [StructuredItem] {
    let text = transcript.text
    
    // Split on topic transition phrases
    let separators = [
        ". also ", ". and also ", ". another thing ", ". oh and ",
        ". one more thing ", ". besides that ", ". on top of that ",
        ". separately ", ". plus ", ". and then ", ". the other thing ",
        ". also,", ". and ", // Weaker separators — use as fallback
    ]
    
    var segments: [String] = []
    var remaining = text.lowercased()
    
    // Try splitting on each separator, strongest first
    for separator in separators {
        if remaining.contains(separator) {
            let parts = remaining.components(separatedBy: separator)
            if parts.count > 1 {
                segments.append(contentsOf: parts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                remaining = "" // Successfully split
                break
            }
        }
    }
    
    // If no separators found, try splitting on sentence boundaries
    if segments.isEmpty {
        segments = text.components(separatedBy: ". ")
            .filter { $0.trimmingCharacters(in: .whitespaces).count > 10 }
    }
    
    // If still just one segment, use the whole transcript as one item
    if segments.isEmpty {
        segments = [text]
    }
    
    // For each segment, do basic categorization using keyword matching
    return segments.map { segment in
        let category = matchCategory(segment, categories: industryConfig.categories.defaults)
        let urgency = estimateUrgency(segment)
        let action = generateBasicAction(segment)
        
        return StructuredItem(
            content: segment.trimmingCharacters(in: .whitespaces).prefix(200).capitalizingFirstLetter(),
            category: category,
            urgency: urgency,
            actionItem: action,
            sourceQuote: segment,
            isFromFallback: true  // Flag so UI can show warning
        )
    }
}

func matchCategory(_ text: String, categories: [Category]) -> String {
    // Simple keyword matching against industry config
    let lowered = text.lowercased()
    
    // Score each category by keyword hits
    var bestCategory = categories.last?.name ?? "General"  // Default to last (usually General)
    var bestScore = 0
    
    for category in categories {
        // Use the categorization hints from the industry config
        var score = 0
        // Add keyword matching logic here based on config.ai.categorization_hints
        if score > bestScore {
            bestScore = score
            bestCategory = category.name
        }
    }
    
    return bestCategory
}

func estimateUrgency(_ text: String) -> String {
    let lowered = text.lowercased()
    let urgentKeywords = ["broken", "down", "not working", "leaking", "failed",
                          "safety", "hazard", "emergency", "immediately", "urgent",
                          "dangerous", "fire", "flood", "injury", "complaint"]
    
    for keyword in urgentKeywords {
        if lowered.contains(keyword) { return "urgent" }
    }
    return "normal"
}

func generateBasicAction(_ text: String) -> String {
    let lowered = text.lowercased()
    
    if lowered.contains("broken") || lowered.contains("not working") || lowered.contains("down") {
        return "Schedule repair or replacement"
    }
    if lowered.contains("running low") || lowered.contains("out of") || lowered.contains("86") {
        return "Reorder or restock"
    }
    if lowered.contains("training") || lowered.contains("schedule") || lowered.contains("hire") {
        return "Confirm schedule and notify team"
    }
    if lowered.contains("complaint") || lowered.contains("issue") || lowered.contains("problem") {
        return "Investigate and follow up"
    }
    
    return "Review and take action"
}
```

---

## Step 6: User Review Screen — COLLECT THE TRAINING SIGNAL

When validation confidence is low, show a review prompt. When the user edits items, capture what they changed. This is your feedback loop for improving the AI over time.

```swift
struct UserEdit {
    let originalItem: StructuredItem
    let editedItem: StructuredItem
    let editType: EditType
    let timestamp: Date
    let transcriptId: String
}

enum EditType {
    case splitItem           // User split 1 item into 2 (AI merged)
    case mergedItems         // User merged 2 items into 1 (AI over-split)
    case changedCategory     // User corrected the category
    case changedUrgency      // User corrected urgency level
    case editedContent       // User rewrote the content
    case editedAction        // User rewrote the action item
    case deletedItem         // User removed a hallucinated item
    case addedItem           // User added an item the AI missed
}

// Log every edit for future analysis
func logUserEdit(edit: UserEdit) {
    // Store locally and sync to backend
    // This data tells you:
    // - How often the AI merges items (splitItem edits)
    // - How often it drops items (addedItem edits)
    // - How often it hallucinates (deletedItem edits)
    // - Which categories it gets wrong most often
    // - Which urgency levels it misjudges
    
    // Over time, use this data to:
    // 1. Identify patterns in AI failures
    // 2. Add specific examples to the prompt
    // 3. Adjust category/urgency logic
    // 4. Build industry-specific correction rules
}
```

### Review Screen UI Behavior

**High confidence (≥0.85):** Show structured items normally. No special prompts. User can still edit anything.

**Medium confidence (0.60–0.84):** Show a subtle banner: "We structured your note. Tap any item to adjust." Highlight items with warnings (possible merge, possible hallucination) with a gentle indicator.

**Low confidence (<0.60):** Show a more prominent banner: "We had trouble with some parts of your recording. Please review these items." Items with warnings get a yellow/amber highlight. The "Did we get this right?" prompt appears.

**Fallback mode (local structuring used):** Show a banner: "Structured offline — AI refinement will update when you're connected." Items are editable but labeled as local estimates.

---

## The Test Suite — PROVE IT WORKS BEFORE YOU SHIP

Build this set of test transcripts and run them against your structuring pipeline every time you change the prompt. This is your regression test.

### Single-Topic Tests (Should produce exactly 1 item)

```
Test 1.1: "The walk-in cooler is making a weird noise, sounds like the compressor might be going bad."
Expected: 1 item, Maintenance, Urgent

Test 1.2: "We need to order more napkins, we're running low."
Expected: 1 item, Inventory, Normal

Test 1.3: "Sarah's doing a great job, just wanted to note that for the record."
Expected: 1 item, Staff, Low
```

### Two-Topic Tests (Should produce exactly 2 items)

```
Test 2.1: "The fryer is making that noise again, and also we're completely out of salmon so 86 that for tomorrow."
Expected: 2 items (Maintenance + Inventory)

Test 2.2: "Room 412 needs a new AC unit, and the Anderson party is checking in tomorrow in suite 801."
Expected: 2 items (Rooms/Maintenance + Front Desk)

Test 2.3: "The forklift needs maintenance and we're short three people for swing shift."
Expected: 2 items (Equipment + Staff)
```

### Three-Topic Tests (Should produce exactly 3 items — the critical test)

```
Test 3.1: "The walk-in cooler is making noise again, we're out of salmon so 86 that for tomorrow, and tell Sarah she's training the new host on Thursday."
Expected: 3 items (Maintenance + Inventory + Staff)

Test 3.2: "Room 412 AC is still broken after two complaints, the VIP Anderson party needs amenities in 801 tomorrow, and third floor supply closet needs a full restock."
Expected: 3 items (Rooms + Front Desk + Housekeeping)

Test 3.3: "Forklift 3 is pulling left, the Sysco delivery was short 12 cases, and there's a wet spot by dock 4."
Expected: 3 items (Equipment + Receiving + Safety)
```

### Stress Tests (4+ topics, casual speech, edge cases)

```
Test 4.1: "OK so the fryer is down, we 86'd the fish, Marcus called in sick, the health inspector is coming Tuesday, and oh yeah the ice machine is leaking again."
Expected: 5 items

Test 4.2: "Everything's fine except the usual stuff, the cooler's still noisy but it's working."
Expected: 1 item (not 0 — "everything's fine" doesn't mean no items)

Test 4.3: "Um so like the thing, you know, the dishwasher, it's uh, it's not working again. And um we also need to like order more of those, uh, the paper towels."
Expected: 2 items (even with heavy filler words)

Test 4.4: (Empty/silence)
Expected: 0 items with a note "No operational content detected"

Test 4.5: "Had a great shift, nothing to report."
Expected: 0 items or 1 informational item ("Shift completed with no issues")

Test 4.6: "The fryer is broken and the grill is broken."
Expected: 2 items (NOT 1 item about "cooking equipment" — these are separate)

Test 4.7: "Tell the morning crew about the cooler. The cooler's been making noise. I already called the repair company about the cooler."
Expected: 1 item (same topic mentioned 3 times — should NOT be 3 items)
```

### Industry-Specific Tests

```
Test 5.1 (Restaurant): "We're low on the special salmon, 86 the crudo. Table 7 complained about wait times. And the POS terminal by the bar is frozen."
Expected: 3 items (Inventory + FOH + Maintenance)

Test 5.2 (Construction): "The framing on the east wall is a quarter inch off spec, need an RFI. Concrete delivery confirmed for Thursday. And I noticed the fall protection on scaffold 3 is missing a guardrail."
Expected: 3 items (Quality + Materials + Safety)

Test 5.3 (Hotel): "Guest in 302 says the shower pressure is low, could be the same issue as last month. The wedding party needs the ballroom set for 200 by Friday. And we need to comp room 415 for the noise complaint."
Expected: 3 items (Rooms/Maintenance + Front Desk + Guest Issues)
```

### Scoring

Run all tests. For each test:
- **Correct item count:** +1 point
- **All categories correct:** +1 point
- **All urgency levels correct:** +1 point
- **All action items actionable:** +1 point
- **No hallucinated content:** +1 point
- **Max per test: 5 points**

**Target: ≥85% overall score (≥4.25 average per test)**

If you're below 85%, the prompt needs work before you ship. Adjust the system prompt, add failing test cases as examples in the prompt, and re-run.

---

## Prompt Improvement Loop

When test scores are low, here's how to improve:

### 1. Add Few-Shot Examples to the Prompt

If the AI keeps merging 2 items into 1, add an explicit example to the system prompt:

```
EXAMPLE OF CORRECT BEHAVIOR:

Transcript: "The fryer is broken and we're out of salmon."

CORRECT (2 items):
[
  { "content": "Fryer is broken", "category": "Maintenance", ... },
  { "content": "Out of salmon", "category": "Inventory", ... }
]

WRONG (1 item):
[
  { "content": "Fryer is broken and we're out of salmon", "category": "Kitchen", ... }
]

The WRONG output merged two distinct operational issues into one. Never do this.
```

### 2. Add Negative Examples for Common Failures

```
COMMON MISTAKES TO AVOID:

- Do NOT combine "equipment broken" and "inventory low" into one "kitchen issue"
- Do NOT drop brief mentions like "oh and tell Sarah about Thursday"
- Do NOT assign "urgent" to informational items like staff schedules
- Do NOT generate items about things the speaker didn't mention
- Do NOT use "General" as a category when a more specific one applies
```

### 3. Adjust Temperature

If output is inconsistent between identical inputs, lower temperature further (try 0.05). If output is too rigid and misses nuance, raise slightly (try 0.15). Never go above 0.2 for structuring.

### 4. Switch Models for Edge Cases

If gpt-4o-mini consistently fails on 4+ topic recordings, try routing those to gpt-4o. Use the local topic count estimate: if estimatedTopicCount > 3, use the stronger model.

---

## Summary: The Complete Pipeline

```
1. Record audio (AVFoundation)
2. Transcribe on-device (Speech framework, capture confidence scores)
3. Clean transcript (remove fillers, detect topic boundaries)
4. Send to AI (structured prompt + industry context + JSON schema)
   - Temperature: 0.1
   - Model: gpt-4o-mini (upgrade to gpt-4o for complex recordings)
   - Timeout: 15s, fallback at 30s
5. Validate response (source quote check, coverage check, hallucination check)
6. Calculate confidence score
7. If confidence ≥ 0.7: show items on review screen normally
   If confidence < 0.7: show with "Did we get this right?" prompt
   If AI fails entirely: use local fallback, show "Structured offline" banner
8. User reviews and edits
9. Log all edits as training signal
10. Publish note to feed
```

Build this, run the test suite until you hit 85%+, and your users will trust the product with their shift.
