---
name: rephrase
description: Rephrase pasted text to be clearer and more empathetic while preserving Dong's voice. Use when the user pastes text and asks to rephrase, reword, soften, clarify, or rework a message — typically Slack messages, MR comments, emails, or other written communication.
---

# Rephrase

The user has pasted some text and wants it rephrased to be clearer and more empathetic, in their voice.

## Input

The text to rephrase will be provided as the argument to `/rephrase`, or the user will paste it in the next message after invoking the command.

If no text was passed in and the previous message has no obvious target text, ask: "What would you like me to rephrase?" and wait for the paste. Do not guess.

## What to do

Rewrite the text so it:
- Reads more clearly. Cut filler, vague qualifiers, and redundant phrasing.
- Lands more empathetically. Acknowledge the reader's perspective when relevant. Soften blunt phrasing without losing the point.
- Stays the same rough length. Don't pad it out, don't shrink it to a one-liner.
- Sounds like the user wrote it, not an AI.

## Voice rules (non-negotiable)

- **No exclamation points.** Anywhere.
- **No em dashes (—).** Use commas, periods, or parentheses instead.
- **No AI-sounding constructions.** Avoid: "leveraged", "streamlined", "key takeaways", "moving forward", "in order to", "I hope this helps", "feel free to", "delve into", "navigate", "robust", "seamless", "ensure", "kindly".
- **Short sentences. Active voice.** Concrete over abstract.
- **Casual but professional**, like talking to a colleague.
- Lowercase "i" is fine in casual contexts (Slack, DMs). Use proper capitalization for emails or formal MR descriptions.
- Acknowledge feedback or mistakes plainly. "Good callout, changed it." "Oops, my bug, fixed." No over-apologizing.
- When pushing back, stay non-confrontational. Don't say someone is wrong. State the current behavior matter-of-factly and link to evidence if possible.

## Output

Return ONLY the rephrased text. No preamble like "Here's the rephrased version:". No trailing explanation of what you changed. No quote blocks unless the original was already in one. Just the text, ready to copy-paste.

If the original had multiple paragraphs or a clear structure (bullets, sections), preserve that structure in the rephrased version.

If the original is already good and rephrasing would make it worse, say so in one short sentence instead of forcing a rewrite.
