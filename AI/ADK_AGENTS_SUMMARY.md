# ADK Agents Summary

## States

┌──────────────────────┬──────────────────────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Variable             │ Description                          │ Used in                                                                                             │
├──────────────────────┼──────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ {language?}          │ Target language for learning         │ All agents                                                                                          │
│ {language_level?}    │ User's proficiency level             │ story_agent, video_agent, role_master_agent, word_smith_agent, text_chat, voice_chat                │
│ {difficulty?}        │ User's selected difficulty           │ story_agent, video_agent, role_master_agent, word_smith_agent, word_generator_agent                 │
│ {story_subject?}     │ Topic/subject of the story/lesson    │ story_agent, video_agent, role_master_agent, word_generator_agent, text_chat, voice_chat           │
│ {description?}       │ Description of the subject           │ story_agent, video_agent, role_master_agent, word_generator_agent, text_chat, voice_chat            │
│ {story?}             │ The story text itself                │ text_chat, voice_chat                                                                               │
│ {words_list?}        │ Vocabulary words list                │ story_agent, word_smith_agent, role_master_agent, text_chat, voice_chat, analyze_agent               │
│ {words_srs_state?}   │ SRS (spaced repetition) state for    │ word_smith_agent                                                                                    │
│                      │ words                                │                                                                                                     │
│ {analysis_result?}   │ Analysis from the analyze_agent      │ text_chat, voice_chat                                                                               │
│ {transcript?}        │ Conversation transcript              │ analyze_agent                                                                                       │
│ {previous_analysis?} │ Previous analysis result             │ analyze_agent                                                                                       │
│ {scenario?}          │ Story scenario details               │ story_agent, video_agent                                                                           │
│ {video_story?}       │ Video story content                  │ video_agent                                                                                         │
│ {lesson_type?}       │ Type of lesson                       │ analyze_agent                                                                                       │

└──────────────────────┴──────────────────────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────┘

## Comprehensive Agent Tables
| Directory | Agent Name | Model | Description |
|-----------|------------|-------|-------------|
| analyze_agent | Analyze_Agent | gemini-2.5-flash | Analyzes user's language proficiency and provides structured scoring |
| corrector_agent | corrector_agent | gemini-2.5-flash | Corrects language mistakes |
| definition_agent | definition_agent | gemini-2.5-flash-lite | Provides simple word/phrase definitions for beginners |
| import_agent | ImportAgent | gemini-1.5-flash | Imports learning content from YouTube/PDFs/Text |
| role_master_agent | RolePlayConversationAgent | gemini-live-2.5-flash-native-audio | Role-play master for immersive language scenarios |
| story_agent | StoryGeneratorSystem | gemini-2.5-flash | Creates captivating stories to teach vocabulary |
| text_chat | QuizPresenter | gemini-2.5-flash | Text-based comprehension Q&A |
| voice_chat | QuizPresenter | gemini-live-2.5-flash-native-audio | Voice-based comprehension Q&A |
| word_generator_agent | WordGeneratorAgent | gemini-2.5-flash-lite | Generates words/sentences/idioms for a topic |
| word_smith_agent | WordSmithAgent | gemini-live-2.5-flash-native-audio | Teaches words with definitions and examples |
| video_agent | VideoStoryGeneratorSystem | gemini-2.5-flash | Generates cinematic story videos |

---

| Directory | Subagents | Tools | Expected Output |
|-----------|-----------|-------|-----------------|
| analyze_agent | - | - | JSON: user_performance_summary, language_level, understanding_percentage, expression_percentage, communication_percentage, word_scores |
| corrector_agent | - | - | Corrected sentence with brief praise and error explanation |
| definition_agent | - | - | Simple word/phrase definition in {language?} |
| import_agent | - | import_tool | {status, import_id, title, lessons[], metadata} |
| role_master_agent | scenario_generator | AgentTool | Scenario description, communication feedback & score |
| story_agent | scenario_writer, story_writer, story_analyzer_agent | generate_image_tool | Story with synopsis, characters, 5-scene plot, images, 7-10 questions |
| text_chat | corrector_agent | AgentTool | quiz_result |
| voice_chat | corrector_agent | AgentTool | quiz_result |
| word_generator_agent | - | - | {content: List[str]} (ordered, easiest first) |
| word_smith_agent | - | - | Word definitions, examples, user practice, SRS-aware teaching |
| video_agent | scenario_writer, video_story_agent, story_analyzer_agent | video_tool | {status, video_path, transcript[{text, start, end}]} |

---

## Agent Dependencies

```
text_chat ──────► corrector_agent
voice_chat ─────► corrector_agent
role_master_agent ──► scenario_generator
story_agent ──────► scenario_writer
                 ► story_writer ────► generate_image_tool
                 ► story_analyzer_agent
video_agent ────► scenario_writer
                 ► video_story_agent ────► video_tool
                 ► story_analyzer_agent
```

## Frontend → Agent State Mapping

How `Frontend/badya_app/lib` passes state variables when calling agents:

### 1. word_generator_agent
**File:** `services/adk_service.dart:generateAndCacheWords()`
**State passed:**
```dart
{
  'story_subject': subject,       // → {story_subject?} in word_generator_instructions.py
  'description': description,     // → {description?}
  'language': language,           // → {language?}
  'difficulty': difficulty,       // → {difficulty?}
}
```
**Used in:** `word_generator_agent/word_generator_instructions.py` (lines 37, 43, 16, 19-20)

### 2. analyze_agent
**File:** `services/adk_service.dart:runAnalyzeAgent()`
**State passed:**
```dart
{
  'topicId': topicId,             // internal tracking (not used by agent)
  'transcript': transcript,       // → {transcript?} in analyze_instructions.py
  'language': language,           // → {language?}
  'words_list': wordsList,        // → {words_list?} (optional)
  'previous_analysis': prior,     // → {previous_analysis?} (optional)
  'lesson_type': lessonType,      // → {lesson_type?} in analyze_instructions.py
}
```
**Used in:** `analyze_agent/analyze_instructions.py` (lines 2, 107, 116, 119)

### 3. story_agent
**File:** `lesson_paths_page.dart:_startReadAndWrite()`
**State passed:**
```dart
{
  'story_subject': subjectTitle,  // → {story_subject?} in story_instructions.py
  'description': description,     // → {description?}
  'language': language,           // → {language?}
  'words_list': words.join(', '), // → {words_list?} (used by story_analyzer)
  'language_level': level,        // → {language_level?}
  'difficulty': difficulty,       // → {difficulty?}
}
```
**Used in:** `story_agent/story_instructions.py` (scenario: lines 5, 7, 11, 37, 43, 50, 61-64; story: lines 67, 78, 96, 99, 102, 104, 110-112)

### 4. video_agent
echo_chamber
**File:** `lesson_paths_page.dart:_startEchoChamber()`
**State passed:**
```dart
{
  'story_subject': subjectTitle,  // → {story_subject?} in video_story_instructions.py
  'description': description,     // → {description?}
  'language': language,           // → {language?}
  'words_list': words.join(', '), // → NOT used in video_agent instructions
  'language_level': level,        // → {language_level?}
  'difficulty': difficulty,       // → {difficulty?}
}
```
**Used in:** `video_agent/video_story_instructions.py` (scenario: lines 7, 11, 14, 43, 46, 49; story: lines 64, 83, 86, 88, 94-96, 113)

### 5. word_smith_agent
**File:** `lesson_paths_page.dart` (word_smith button)
**State passed:**
```dart
{
  'story_subject': subjectTitle,  // → {story_subject?} (NOT used in word_smith_instructions.py)
  'words_list': words.join(', '), // → {words_list?} in word_smith_instructions.py
  'language': currentLanguage,    // → {language?}
  'language_level': level,        // → {language_level?}
  'difficulty': difficulty,       // → {difficulty?}
}
```
**Note:** The `story_subject` is passed but NOT used by word_smith_agent instructions.
**SRS State (added in voice_chat_page.dart):**
```dart
'words_srs_state': wordsSrsStateJson  // → {words_srs_state?} in word_smith_instructions.py
```
**Used in:** `word_smith_agent/word_smith_instructions.py` (lines 3, 19, 25, 51, 56)

### 6. role_master_agent
**File:** `lesson_paths_page.dart` (role_master button)
**State passed:**
```dart
{
  'story_subject': subjectTitle,  // → {story_subject?} in role_master_instructions.py
  'words_list': words.join(', '), // → {words_list?} (vocabulary to include)
  'language': currentLanguage,    // → {language?}
  'language_level': level,        // → {language_level?}
  'difficulty': difficulty,       // → {difficulty?}
}
```
**Note:** `description` is NOT passed to role_master_agent from frontend (the agent instruction references {description?} but frontend doesn't send it).
**Used in:** `role_master_agent/role_master_instructions.py` (scenario_gen: lines 2, 10, 16-18, 29; role_play: lines 38, 44, 59)

### 7. text_chat (QuizPresenter)
**File:** `chat_page.dart:_initTextChat()`
**State passed:**
```dart
{
  'topic_id': topicId,            // internal (NOT used by text_chat instructions)
  'story': initialStory,          // → {story?} in chat_instructions.py
  'story_subject': storySubject,  // → {story_subject?}
  'analysis_result': analysis,    // → {analysis_result?}
  'language_level': level,        // → {language_level?}
  'description': description,     // → {description?}
  'words_list': wordsList,        // → {words_list?}
}
```
**Note:** `{language?}` is NOT passed here — text_chat relies on corrector_agent's language setting.
**Used in:** `text_chat/chat_instructions.py` (lines 5, 11, 26, 33, 53-54, 57, 60, 63)

### 8. voice_chat (QuizPresenter / word_smith / role_master)
**File:** `voice_chat_page.dart:_initVoiceChat()`
**State passed:**
```dart
{
  'story_subject': storySubject,  // → {story_subject?}
  'description': description,     // → {description?}
  'words_list': words.join(', '), // → {words_list?}
  'language': learningLanguage,   // → {language?}
  'language_level': level,        // → {language_level?}
  'story': widget.story,          // → {story?} (conditional)
  'analysis_result': analysis,    // → {analysis_result?} (conditional)
  'words_srs_state': srsJson,     // → {words_srs_state?} (only for word_smith_agent)
}
```
**Used in:** `voice_chat/chat_instructions.py` (lines 5, 11, 27, 34, 54-55, 58, 61, 65)

### 9. corrector_agent
**File:** `chat_page.dart:_initCorrector()` and `voice_chat_page.dart`
**State passed:**
```dart
{
  'language': learningLanguage,   // → {language?} in corrector_agent/agent.py
}
```
**Used in:** `corrector_agent/agent.py` (lines 6, 11, 14-15, 18, 21)

### 10. definition_agent
**File:** `chat_page.dart:_createDefinitionSession()`, `story_page.dart:_createDefinitionSession()`, etc.
**State passed:**
```dart
{
  'language': learningLanguage,   // → {language?} in definition_agent/agent.py
}
```
**Note:** The `{language?}` in definition_agent's instruction is used but the agent doesn't receive any other variables.
**Used in:** `definition_agent/agent.py` (lines 6-8)

---

## Summary: Variable Usage by Agent

| Variable | Agents that USE it (instructions) | Agents that RECEIVE it (frontend) |
|----------|-----------------------------------|-----------------------------------|
| `{language?}` | All agents | All agents |
| `{language_level?}` | story_agent, video_agent, word_smith_agent, role_master_agent, text_chat, voice_chat | story_agent, video_agent, word_smith_agent, role_master_agent, text_chat, voice_chat |
| `{difficulty?}` | story_agent, video_agent, word_smith_agent, word_generator_agent, role_master_agent | story_agent, video_agent, word_smith_agent, word_generator_agent, role_master_agent |
| `{story_subject?}` | story_agent, video_agent, word_generator_agent, role_master_agent, text_chat, voice_chat | story_agent, video_agent, word_smith_agent*, role_master_agent, text_chat, voice_chat, word_generator_agent |
| `{description?}` | story_agent, video_agent, word_generator_agent, role_master_agent*, text_chat, voice_chat | story_agent, video_agent, word_generator_agent, text_chat, voice_chat |
| `{story?}` | text_chat, voice_chat | text_chat, voice_chat (conditional) |
| `{words_list?}` | story_analyzer (story_agent), word_smith_agent, role_master_agent, text_chat, voice_chat, analyze_agent | story_agent, video_agent, word_smith_agent, role_master_agent, text_chat, voice_chat, analyze_agent |
| `{words_srs_state?}` | word_smith_agent | word_smith_agent (from voice_chat_page only) |
| `{analysis_result?}` | text_chat, voice_chat | text_chat, voice_chat (conditional) |
| `{transcript?}` | analyze_agent | analyze_agent (from runAnalyzeAgent) |
| `{previous_analysis?}` | analyze_agent | analyze_agent (from runAnalyzeAgent) |
| `{lesson_type?}` | analyze_agent | analyze_agent (from runAnalyzeAgent) |
| `{scenario?}` | story_writer (story_agent), video_story_agent (video_agent) | NOT passed directly — generated by scenario_writer subagent |
| `{video_story?}` | video_agent questions | NOT passed from frontend — generated by video_story_agent |

* = variable is passed but not used in instruction, or instruction references it but frontend doesn't send it.
