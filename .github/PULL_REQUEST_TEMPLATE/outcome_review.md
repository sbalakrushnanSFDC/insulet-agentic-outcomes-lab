# Outcome Publication PR

## Feature

- **Jira Key:** <!-- e.g. NGOMCT-344 -->
- **Feature Summary:** <!-- One-sentence description from Jira title -->
- **Outcome Path:** <!-- e.g. outcomes/2026-03/NGOMCT-344/ -->
- **Pipeline Run Date:** <!-- YYYY-MM-DD -->
- **Iteration:** <!-- First / v2 / v3 -->

---

## Summary

<!-- 3-5 sentences describing what was produced in this pipeline run.
  What did the agent do? What worked? What is the key gap or limitation?
  Why is this worth publishing to the gallery? -->

---

## Author Checklist

Complete all items before requesting review.

### Required

- [ ] `outcome-metadata.md` is filled in — source refs, assumptions, known gaps are all populated
- [ ] `pipeline/status.json` reflects the actual pipeline state (not edited to show false passes)
- [ ] `pipeline/traceability.json` is present (even if partial)
- [ ] At least `00-intake.md` and `01-plan.md` are present in `pipeline/`
- [ ] No `.env` files, credentials, or API keys in the diff
- [ ] No `raw_payload.json` or full Jira API responses in the diff
- [ ] No Salesforce source code (`force-app/`, `*.cls`, `*.js`) in the diff
- [ ] No `MEMORY.md` or files containing org aliases/sandbox URLs in the diff
- [ ] Jira URL in `outcome-metadata.md` is a valid link to the story
- [ ] Branch follows naming convention: `outcome/{JIRA-KEY}-{YYYY-MM}`
- [ ] At least one cross-functional reviewer assigned (not the operator)

### If applicable

- [ ] `solution/{JIRA-KEY}-Solution-Architecture.md` is present (if DOC step completed)
- [ ] `review-log.md` is initialized with the operator's self-assessment
- [ ] Previous iteration referenced in `outcome-metadata.md` (if this is v2+)

---

## Known Gaps

<!-- List the gaps you are aware of in this outcome. These should also appear in outcome-metadata.md.
  Do not hide gaps — reviewers need to know what to look for.

  Example:
  - Confluence CON-13 body was not retrieved (authentication required); AC was inferred from Jira description and sibling feature NGOMCT-91
  - E2E validation was a paper exercise; SF CLI had a silent auth failure on orgsyncng
-->

1. 
2. 

---

## Reviewer Guidance

<!-- Optional: tell reviewers what to focus on.
  Example:
  - Please pay particular attention to the derived ACs in 01-plan.md — I am not confident AC-4 is correctly specified
  - The security findings in 07-security.md are all marked resolved; please verify the logic in 05-build-fix.md
-->
