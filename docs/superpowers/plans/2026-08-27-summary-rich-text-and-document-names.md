# Summary Rich Text And Document Names Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to format AI summaries with common Markdown controls and persist separate custom names for transcript and summary exports.

**Architecture:** Keep Markdown text as the document format. Add pure Markdown edit and export-name helpers, persist two optional document-name fields on `ResearchCapture`, and keep Flutter widgets responsible only for invoking helpers and rendering state. Existing recording names, ASR calls, and export transport remain unchanged.

**Tech Stack:** Flutter Material, Dart, Drift/SQLite, flutter_test, existing `share_plus` exporter.

---

## File Structure

- `lib/features/research_beta/domain/research_capture.dart`: Add `ResearchDocumentType`, separate optional document-name fields, title accessors, and immutable rename updates that survive processing retries.
- `lib/core/documents/document_file_name.dart`: Pure validation and filename construction for custom export base names.
- `lib/core/persistence/tables/research_captures.dart`: Add nullable `transcriptTitle` and `summaryTitle` columns.
- `lib/core/persistence/app_database.dart`: Upgrade schema from 4 to 5 and add the two columns for version-4 databases.
- `lib/core/persistence/app_database.g.dart`: Drift-generated database code.
- `lib/features/research_beta/data/drift_research_capture_repository.dart`: Map both document-name fields in rows and companions.
- `lib/features/research_beta/application/research_capture_library_controller.dart`: Validate and persist independent document renames as an edit action.
- `lib/features/research_beta/presentation/research_markdown_editing.dart`: Pure `TextEditingValue` transformations for the eleven toolbar actions and link insertion.
- `lib/features/research_beta/presentation/research_markdown_preview.dart`: Focused Markdown preview widgets for the supported syntax.
- `lib/features/research_beta/presentation/research_document_rename_sheet.dart`: Reusable document-name bottom sheet, following the existing recording rename sheet style.
- `lib/features/research_beta/presentation/research_markdown_document_editor.dart`: Keep editor state, invoke pure transforms, show two toolbar rows and link dialog, and delegate preview rendering.
- `lib/features/research_beta/presentation/research_transcript_editor.dart`: Accept and display a custom title and expose a rename action.
- `lib/features/research_beta/presentation/research_capture_content.dart`: Thread document display names and rename callbacks into transcript and summary panels.
- `lib/features/local_recording/presentation/local_recording_detail_page.dart`: Show rename sheets, persist names through the library controller, and create export filenames from document type.
- `test/features/research_beta/...`: Domain, persistence, application, Markdown edit/preview, and panel tests.
- `test/features/local_recording/presentation/local_recording_detail_page_test.dart`: Validate separate renames and export-name priority.

### Task 1: Add Separate Persistent Document Names

**Files:**
- Modify: `lib/features/research_beta/domain/research_capture.dart`
- Modify: `lib/core/persistence/tables/research_captures.dart`
- Modify: `lib/core/persistence/app_database.dart`
- Modify: `lib/features/research_beta/data/drift_research_capture_repository.dart`
- Modify: `lib/core/persistence/app_database.g.dart` (generated)
- Modify: `test/features/research_beta/data/drift_research_capture_repository_test.dart`
- Create: `test/features/research_beta/domain/research_capture_test.dart`

- [ ] **Step 1: Write failing domain and repository tests**

Add a domain test which creates a completed capture, calls `withDocumentTitle(ResearchDocumentType.transcript, '访谈转写')` and `withDocumentTitle(ResearchDocumentType.summary, '访谈总结')`, then verifies the two values remain distinct after `restartTranscription()` and `restartSummary()`. Add a Drift round-trip test that saves the same capture and verifies both values after `findById`.

```dart
expect(saved.transcriptTitle, '访谈转写');
expect(saved.summaryTitle, '访谈总结');
expect(saved.restartSummary().summaryTitle, '访谈总结');
```

- [ ] **Step 2: Run the focused tests and verify they fail because the fields do not exist**

Run: `flutter test test/features/research_beta/domain/research_capture_test.dart test/features/research_beta/data/drift_research_capture_repository_test.dart --reporter compact`

Expected: compilation failure referring to missing `ResearchDocumentType`, `transcriptTitle`, `summaryTitle`, or `withDocumentTitle`.

- [ ] **Step 3: Extend the domain model and table schema**

In `research_capture.dart`, add:

```dart
enum ResearchDocumentType { transcript, summary }

extension ResearchDocumentTypeLabel on ResearchDocumentType {
  String get defaultTitle => switch (this) {
    ResearchDocumentType.transcript => '转写',
    ResearchDocumentType.summary => 'AI 总结',
  };
}
```

Add nullable constructor fields `transcriptTitle` and `summaryTitle`, a `documentTitle(ResearchDocumentType type)` accessor returning the custom non-empty value or `type.defaultTitle`, and `withDocumentTitle` that trims a non-empty value and updates only the chosen field. Include both fields in `copyWith`, `restartSummary`, and `restartTranscription` so regeneration never erases user names.

Add two nullable columns in `research_captures.dart`:

```dart
TextColumn get transcriptTitle => text().nullable()();
TextColumn get summaryTitle => text().nullable()();
```

Set `schemaVersion` to `5`. Preserve the existing `from < 3` creation branch; for databases created at version 3 or 4, add `asrSegmentsJson` only when `from < 4`, then add `transcriptTitle` and `summaryTitle` when `from < 5`.

Map both fields in `_captureFromRow`, `_captureRow`, and `_captureCompanion` using `Value(value.transcriptTitle)` and `Value(value.summaryTitle)`.

- [ ] **Step 4: Regenerate Drift output**

Run: `dart run build_runner build --delete-conflicting-outputs`

Expected: `lib/core/persistence/app_database.g.dart` contains the two new nullable `research_captures` columns and no generated-code errors.

- [ ] **Step 5: Run the focused tests and verify they pass**

Run: `flutter test test/features/research_beta/domain/research_capture_test.dart test/features/research_beta/data/drift_research_capture_repository_test.dart --reporter compact`

Expected: PASS.

- [ ] **Step 6: Add an explicit v4 migration test**

In `drift_research_capture_repository_test.dart`, create a v4 SQLite file containing the pre-change `research_captures` definition plus `PRAGMA user_version = 4`, open it through `AppDatabase.forTesting`, and verify the two new columns are readable as `null` for a pre-existing row.

- [ ] **Step 7: Run the migration test and commit the persistence slice**

Run: `flutter test test/features/research_beta/data/drift_research_capture_repository_test.dart --reporter compact`

Expected: PASS.

```powershell
git add lib/features/research_beta/domain/research_capture.dart lib/core/persistence/tables/research_captures.dart lib/core/persistence/app_database.dart lib/core/persistence/app_database.g.dart lib/features/research_beta/data/drift_research_capture_repository.dart test/features/research_beta/domain/research_capture_test.dart test/features/research_beta/data/drift_research_capture_repository_test.dart
git commit -m "feat: persist transcript and summary document names"
```

### Task 2: Add Safe Document-Name Application Logic

**Files:**
- Create: `lib/core/documents/document_file_name.dart`
- Modify: `lib/features/research_beta/application/research_capture_library_controller.dart`
- Create: `test/core/documents/document_file_name_test.dart`
- Modify: `test/features/research_beta/application/research_capture_library_controller_test.dart`

- [ ] **Step 1: Write failing filename and rename-controller tests**

Test that `DocumentFileName.build` returns `会议纪要.md` for a custom summary title, removes `\\ / : * ? " < > |` and surrounding whitespace, appends exactly one extension, and falls back to `20260825_000000_转写.txt` when no custom name is supplied. Test that `renameDocument` updates only the requested title, records `ResearchCardAction.edited`, and rejects empty or fully illegal names without updating the repository.

```dart
expect(
  DocumentFileName.build(
    customBaseName: '  会议:纪要.md ',
    fallbackTime: DateTime(2026, 8, 25),
    fallbackSuffix: '总结',
    extension: 'md',
  ),
  '会议纪要.md',
);
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run: `flutter test test/core/documents/document_file_name_test.dart test/features/research_beta/application/research_capture_library_controller_test.dart --reporter compact`

Expected: failure because `DocumentFileName` and `renameDocument` do not exist.

- [ ] **Step 3: Implement normalization, export naming, and persistence**

Create a dependency-free helper with:

```dart
abstract final class DocumentFileName {
  static String? normalizeCustomBaseName(String source);
  static String build({
    required String? customBaseName,
    required DateTime fallbackTime,
    required String fallbackSuffix,
    required String extension,
  });
}
```

`normalizeCustomBaseName` trims input, removes path and reserved filename characters, removes a matching trailing extension, and returns `null` when no usable name remains. `build` uses the normalized custom name plus the requested extension, otherwise preserves the existing timestamp-plus-suffix format.

Add `renameDocument(ResearchCapture capture, ResearchDocumentType type, String requestedTitle)` to `ResearchCaptureLibraryController`. It validates with `normalizeCustomBaseName`, throws `ArgumentError` for invalid input, and calls `markHandled(capture.withDocumentTitle(type, normalized), ResearchCardAction.edited)`.

- [ ] **Step 4: Run the focused tests and verify they pass**

Run: `flutter test test/core/documents/document_file_name_test.dart test/features/research_beta/application/research_capture_library_controller_test.dart --reporter compact`

Expected: PASS.

- [ ] **Step 5: Commit the application slice**

```powershell
git add lib/core/documents/document_file_name.dart lib/features/research_beta/application/research_capture_library_controller.dart test/core/documents/document_file_name_test.dart test/features/research_beta/application/research_capture_library_controller_test.dart
git commit -m "feat: add safe document export names"
```

### Task 3: Build Testable Markdown Edit and Preview Primitives

**Files:**
- Create: `lib/features/research_beta/presentation/research_markdown_editing.dart`
- Create: `lib/features/research_beta/presentation/research_markdown_preview.dart`
- Create: `test/features/research_beta/presentation/research_markdown_editing_test.dart`
- Create: `test/features/research_beta/presentation/research_markdown_preview_test.dart`

- [ ] **Step 1: Write failing edit-transform tests**

Cover heading replacement/toggle, bullet/list/checkbox/quote line toggles, divider insertion, bold/italic/underline markers around a selection, and Markdown-link insertion.

```dart
expect(
  ResearchMarkdownEditing.applyLinePrefix(
    const TextEditingValue(text: '事项', selection: TextSelection.collapsed(offset: 0)),
    '# ',
  ).text,
  '# 事项',
);
expect(
  ResearchMarkdownEditing.insertLink(
    const TextEditingValue(text: '资料', selection: TextSelection(baseOffset: 0, extentOffset: 2)),
    url: 'https://example.com',
    fallbackLabel: '链接文字',
  ).text,
  '[资料](https://example.com)',
);
```

- [ ] **Step 2: Run the edit tests and verify they fail**

Run: `flutter test test/features/research_beta/presentation/research_markdown_editing_test.dart --reporter compact`

Expected: compilation failure because `ResearchMarkdownEditing` does not exist.

- [ ] **Step 3: Implement pure Markdown transformations**

Create `ResearchMarkdownEditing` with static methods that accept and return `TextEditingValue`, preserving selection positions. Define constants for `# `, `## `, `- `, `1. `, `- [ ] `, `> `, `**`, `*`, and `<u>`/`</u>`. Line actions must replace a competing heading prefix, remove an identical prefix on a second invocation, and otherwise prepend it. Inline actions wrap the selection or insert `加粗文字` / `斜体文字` / `下划线文字` placeholders. Divider insertion writes `\n\n---\n\n` at the selection. Link insertion produces `[label](url)` without changing surrounding content.

- [ ] **Step 4: Write failing preview tests**

Pump a preview containing headings, unordered and ordered list items, task items, quote, divider, bold, italic, underline, and `[资料](https://example.com)`. Assert that syntax markers are absent where rendered semantics exist, task rows show checkbox icons, quote has a left rule, divider is a `Divider`, and link label uses the link color.

- [ ] **Step 5: Implement focused preview widgets and make tests pass**

Create `ResearchMarkdownPreview` and small private line/inline widgets. Keep parsing deliberately limited to the editor's supported syntax: `#`/`##`, `- `, `1. `, `- [ ]`, `- [x]`, `> `, `---`, `**bold**`, `*italic*`, `<u>underline</u>`, and `[label](url)`. Render unknown input as plain text so existing AI content is never discarded.

Run: `flutter test test/features/research_beta/presentation/research_markdown_editing_test.dart test/features/research_beta/presentation/research_markdown_preview_test.dart --reporter compact`

Expected: PASS.

- [ ] **Step 6: Commit the Markdown primitives**

```powershell
git add lib/features/research_beta/presentation/research_markdown_editing.dart lib/features/research_beta/presentation/research_markdown_preview.dart test/features/research_beta/presentation/research_markdown_editing_test.dart test/features/research_beta/presentation/research_markdown_preview_test.dart
git commit -m "feat: add Markdown editing primitives"
```

### Task 4: Wire the Complete Mobile Editing and Rename UI

**Files:**
- Create: `lib/features/research_beta/presentation/research_document_rename_sheet.dart`
- Modify: `lib/features/research_beta/presentation/research_markdown_document_editor.dart`
- Modify: `lib/features/research_beta/presentation/research_transcript_editor.dart`
- Modify: `lib/features/research_beta/presentation/research_capture_content.dart`
- Modify: `lib/features/local_recording/presentation/local_recording_detail_page.dart`
- Modify: `test/features/research_beta/presentation/research_markdown_document_editor_test.dart`
- Modify: `test/features/research_beta/presentation/research_capture_content_test.dart`
- Modify: `test/features/local_recording/presentation/local_recording_detail_page_test.dart`

- [ ] **Step 1: Write failing widget tests for complete formatting and independent names**

Extend `research_markdown_document_editor_test.dart` to enter editing mode and assert two six/ five-control toolbar rows, then tap heading, italic, checkbox, quote, divider, and link controls before saving. Add a link-dialog test that enters `https://example.com` and verifies the saved Markdown.

Extend `local_recording_detail_page_test.dart` to rename transcript to `访谈转写` and summary to `访谈纪要`, then export both and expect exactly `访谈转写.txt` and `访谈纪要.md`. Keep the existing test for the timestamp fallback names.

- [ ] **Step 2: Run widget tests and verify they fail**

Run: `flutter test test/features/research_beta/presentation/research_markdown_document_editor_test.dart test/features/research_beta/presentation/research_capture_content_test.dart test/features/local_recording/presentation/local_recording_detail_page_test.dart --reporter compact`

Expected: failure because the controls, rename callbacks, and custom export names are not yet present.

- [ ] **Step 3: Add the reusable document rename sheet**

Implement `ResearchDocumentRenameSheet.show` using the same `SafeArea`, keyboard insets, 60-character limit, and `AppButton.primary` pattern as `RenameRecordingSheet`. Accept `documentLabel` and `initialTitle`; use `'$documentLabel 名称'` as the input label. Return `null` on dismissal and untrimmed text only on explicit save so the application layer remains the validation authority.

- [ ] **Step 4: Integrate titles, renaming, and export naming**

Add `title` and `onRename` callbacks to both editor widgets. Render the title in the existing top row and add a tooltip-backed `Icons.drive_file_rename_outline` button adjacent to it. In `ResearchCaptureTranscriptPanel` and `ResearchCaptureSummaryPanel`, derive labels from `capture.documentTitle(type)` and pass document-specific callbacks.

In `LocalRecordingDetailPage`, use the new rename sheet and call `researchLibrary.renameDocument`. When exporting, replace `_documentFileName(suffix:, extension:)` with a document-type method that calls `DocumentFileName.build` using `capture.transcriptTitle` or `capture.summaryTitle`, the recording creation date, and the document's fixed extension. Leave copying, processing, and recording titles untouched.

- [ ] **Step 5: Integrate the two-row summary toolbar and preview**

Replace the old three-button `_FormattingToolbar` with two fixed `Row`s of `IconButton`s. Use tooltip strings: `一级标题`, `二级标题`, `加粗`, `斜体`, `下划线`, `无序列表`, `有序列表`, `待办项`, `引用`, `分割线`, and `插入链接`. Route all non-link actions through `ResearchMarkdownEditing`; the link button opens an `AlertDialog` with URL and optional label fields, then calls `insertLink` only when the URL parses as an absolute `http` or `https` URI. Replace local preview classes with `ResearchMarkdownPreview`.

- [ ] **Step 6: Run widget tests and verify they pass**

Run: `flutter test test/features/research_beta/presentation/research_markdown_document_editor_test.dart test/features/research_beta/presentation/research_capture_content_test.dart test/features/local_recording/presentation/local_recording_detail_page_test.dart --reporter compact`

Expected: PASS.

- [ ] **Step 7: Commit the presentation slice**

```powershell
git add lib/features/research_beta/presentation/research_document_rename_sheet.dart lib/features/research_beta/presentation/research_markdown_document_editor.dart lib/features/research_beta/presentation/research_transcript_editor.dart lib/features/research_beta/presentation/research_capture_content.dart lib/features/local_recording/presentation/local_recording_detail_page.dart test/features/research_beta/presentation/research_markdown_document_editor_test.dart test/features/research_beta/presentation/research_capture_content_test.dart test/features/local_recording/presentation/local_recording_detail_page_test.dart
git commit -m "feat: expand summary editor and document rename UI"
```

### Task 5: Verify Integration and Regression Safety

**Files:**
- Modify only when a test exposes an implementation defect from Tasks 1-4.

- [ ] **Step 1: Format changed Dart sources**

Run: `dart format lib/core/documents/document_file_name.dart lib/core/persistence/app_database.dart lib/core/persistence/tables/research_captures.dart lib/features/research_beta/domain/research_capture.dart lib/features/research_beta/data/drift_research_capture_repository.dart lib/features/research_beta/application/research_capture_library_controller.dart lib/features/research_beta/presentation/research_document_rename_sheet.dart lib/features/research_beta/presentation/research_markdown_editing.dart lib/features/research_beta/presentation/research_markdown_preview.dart lib/features/research_beta/presentation/research_markdown_document_editor.dart lib/features/research_beta/presentation/research_transcript_editor.dart lib/features/research_beta/presentation/research_capture_content.dart lib/features/local_recording/presentation/local_recording_detail_page.dart test/core/documents/document_file_name_test.dart test/features/research_beta/domain/research_capture_test.dart test/features/research_beta/data/drift_research_capture_repository_test.dart test/features/research_beta/application/research_capture_library_controller_test.dart test/features/research_beta/presentation/research_markdown_editing_test.dart test/features/research_beta/presentation/research_markdown_preview_test.dart test/features/research_beta/presentation/research_markdown_document_editor_test.dart test/features/research_beta/presentation/research_capture_content_test.dart test/features/local_recording/presentation/local_recording_detail_page_test.dart`

- [ ] **Step 2: Run the impacted feature suite**

Run: `flutter test test/features/research_beta test/features/local_recording/presentation/local_recording_detail_page_test.dart --reporter compact`

Expected: PASS.

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 4: Review generated and working-tree changes before the final commit**

Run: `git diff --check` and `git status --short`

Expected: no whitespace errors; only intended feature files are staged for this final verification commit. Preserve all pre-existing user changes outside this feature.

- [ ] **Step 5: Commit verification-only corrections if needed**

```powershell
git add <only files changed while resolving verification failures>
git commit -m "test: cover summary document editing"
```
