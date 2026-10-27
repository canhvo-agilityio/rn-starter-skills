# Getting the ticket

The ticket stays where it lives (Jira, GitHub, a document): that's the record the team works from. The ticket file in `docs/tickets/` links to it and never replaces it. Read only: never comment, edit, transition or assign.

## GitHub issues

```bash
bash "<skill-dir>/scripts/fetch-ticket.sh" https://github.com/acme/shop/issues/412
bash "<skill-dir>/scripts/fetch-ticket.sh" acme/shop#412
bash "<skill-dir>/scripts/fetch-ticket.sh" '#412'            # the repo of the current directory
```

Needs the `gh` CLI signed in (`gh auth status`). If it isn't, the script exits 2 with the command the dev runs themselves; don't sign in for them.

The id is the issue number (`412`); the file is `docs/tickets/412.md`. If the team uses another scheme for ticket files already in `docs/tickets/`, follow it.

## Jira

Use the Jira / Atlassian connector when one is connected: find the tool that reads an issue by key and read the summary, description, acceptance criteria field (often a custom field), comments, attachments list and linked issues. Read only.

No connector: ask the dev to paste the ticket (title, description, acceptance criteria and the comments that matter), or to export it. Don't ask for a Jira API token and don't put one in a URL or a header.

Either way, save the text in your scratchpad and run the script on it, so the links and criteria are extracted the same way:

```bash
bash "<skill-dir>/scripts/fetch-ticket.sh" --text-file <scratchpad>/PROJ-412.md --id PROJ-412
```

The id is the issue key (`PROJ-412`).

## Pasted text, documents

Same as Jira without a connector: save, run with `--text-file`, and ask for an id if the text has none (a short kebab-case slug like `order-history` is fine when the team has no tracker).

## A request typed with the command

`/rn-feature thêm nút share ở màn Detail`: no tracker, the dev's words are the ticket. Save them as the ticket text (your scratchpad, then `fetch-ticket.sh --text-file … --id <slug>` for links), use a short id (`detail-share`, or the tracker key if the dev gives one) and `source: dev request`. The requirements are numbered from those words and confirmed with the dev before anything else; what the request leaves out becomes questions for the dev (or the PO they name).

## What the script returns

```json
{
  "id": "412", "source": "https://github.com/acme/shop/issues/412", "title": "Order history",
  "state": "OPEN", "labels": ["feature"], "type": "feature",
  "body": "…", "comments": [{ "author": "pm-anna", "createdAt": "…", "body": "…" }],
  "acceptanceCriteria": ["User sees their orders newest first", "…"],
  "links": { "figma": ["https://www.figma.com/design/…"], "images": ["…png"], "api": ["https://api.dev…/swagger"], "other": [] }
}
```

- `acceptanceCriteria`: lines under a heading such as "Acceptance criteria", "AC", "Definition of done" or "Tiêu chí", plus checkbox items (`- [ ]`). Empty when the ticket has none in a recognizable form; read the body yourself either way.
- `type`: `bug` when a label or the title says so (bug, defect, lỗi), else `feature`. Confirm with the dev when it's unclear.
- `links`: Figma links become the design input, images become screenshots to read, Swagger / OpenAPI links the API input. Images on GitHub need the dev's session: download them with `gh` only if the dev agrees, or ask the dev to save them into the project (`docs/design/<id>/`).
