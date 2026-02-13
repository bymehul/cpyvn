# phone

**Syntax**
```vn
phone open "<contact_name>";
phone msg <side> "<message_text>";
phone close;
```

**Description**
Manages the phone/messaging UI overlay.

- **open**: Opens the phone UI with the specified contact name in the header.
- **msg**: Adds a message to the conversation.
    - **side**: Either `left` (typically for NPCs) or `right` (typically for the player).
    - **message_text**: The content of the message. Supports `${var}` placeholders.
- **close**: Closes the phone UI and clears the message history.

**Example**
```vn
phone open "Alice";
phone msg left "Are you coming to the party tonight?";
narrator "I should probably reply...";
phone msg right "Yeah, I'll be there soon!";
phone msg left "Great! See you then.";
phone close;
```
