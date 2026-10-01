# MeshCore Radio Client for PicoCalc<!-- omit in toc -->

The MeshCore client connects your PicoCalc to a MeshCore companion radio node over TCP, enabling messaging over LoRa mesh networks. It supports direct messages, channel messages, contact browsing, login authentication, battery monitoring, emoji shortcodes, and session logging.

- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Launching the Client](#launching-the-client)
- [Basic Usage](#basic-usage)
  - [Connecting to a Node](#connecting-to-a-node)
  - [Browsing Contacts](#browsing-contacts)
  - [Sending Direct Messages](#sending-direct-messages)
  - [Sending Channel Messages](#sending-channel-messages)
  - [Emoji Shortcodes](#emoji-shortcodes)
  - [Authentication](#authentication)
- [Debug Mode](#debug-mode)
- [Session Logging](#session-logging)
- [Screen Layout](#screen-layout)
- [Commands Reference](#commands-reference)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Message Types](#message-types)
- [Protocol Overview](#protocol-overview)
- [Tips and Best Practices](#tips-and-best-practices)

---

## Getting Started

### Prerequisites

- A MeshCore-compatible radio node (e.g., T-Beam, Heltec, RAK) running the MeshCore companion firmware with TCP server enabled
- Wi-Fi connection between the PicoCalc and the radio node (the node typically runs an AP at `192.168.4.1`)

### Launching the Client

From the PicoCalc shell:

```
mesh                                    -- connects to 192.168.4.1:5555 (defaults)
mesh 192.168.4.1 5555                   -- explicit host and port
mesh 10.0.0.50 5555                     -- connect to a node on your LAN
mesh -d 192.168.4.1 5555               -- connect with debug packet logging
mesh 192.168.4.1 5555 session.log       -- log all output to a file
mesh -d 192.168.4.1 5555 session.log    -- debug mode with logging
```

Or from Lua directly:

```lua
dofile("lua/mesh.lua")
```

The client will auto-connect on launch and display the node name once the handshake completes.

---

## Basic Usage

### Connecting to a Node

The client connects automatically on launch. If the connection drops or you need to reconnect:

```
/connect                      -- reconnect with current settings
/connect 192.168.4.1 5555     -- connect to a different node
/disconnect                   -- disconnect from the node
```

### Browsing Contacts

The node maintains a list of contacts (other radios it has heard). To browse them:

```
/contacts
```

This opens the contact list overlay:

- **Up/Down arrows** - navigate the list
- **Page Up/Page Down** - scroll quickly
- **Enter** - select a contact as your DM target
- **Esc** - return to the chat view

Contacts show a type indicator: `[C]` for companion/chat nodes, `[R]` for repeater nodes.

### Sending Direct Messages

There are three ways to send a direct message:

**1. Select a target, then type freely:**

```
/contacts              -- browse and press Enter on a contact
hello there!           -- sends as DM to selected contact
how are you?           -- subsequent messages also go to that contact
```

**2. Use the /target command:**

```
/target Steve          -- set DM target by name (partial match works)
/target 3              -- set DM target by contact number
hi Steve!              -- sends as DM
```

**3. Use the /msg command for one-off messages:**

```
/msg Steve hello!      -- send DM without changing your default target
/msg 3 hello!          -- by contact number
```

### Sending Channel Messages

MeshCore supports broadcast channel messages (like group chat):

```
/ch 0 hello everyone!  -- send message on channel 0
/ch 1 testing          -- send on channel 1
```

To change your default channel (used when no DM target is set):

```
/ch 2                  -- switch to channel 2
hello!                 -- now sends on channel 2
```

After sending a channel message, you'll see `sent` confirmation. If repeaters forward the message, you'll see `heard 1 repeat`, `heard 2 repeats`, etc.

### Emoji Shortcodes

The PicoCalc terminal cannot display graphical emoji, so the client automatically converts them:

**Incoming messages**: UTF-8 emoji are converted to readable `:shortcode:` text. For example, a thumbs-up emoji appears as `:thumbsup:`.

**Outgoing messages**: You can type shortcodes and they will be converted to real emoji before sending. Recipients on mobile apps will see the graphical emoji.

```
hello :thumbsup:       -- sends with a real thumbs-up emoji
great news :tada:      -- sends with a party popper emoji
:fire: nice work       -- sends with a fire emoji
```

Common shortcodes:

| Shortcode | Emoji | Shortcode | Emoji |
|-----------|-------|-----------|-------|
| `:smile:` | smile | `:thumbsup:` | thumbs up |
| `:thumbsdown:` | thumbs down | `:heart:` | heart |
| `:fire:` | fire | `:100:` | 100 |
| `:tada:` | party | `:wave:` | wave |
| `:joy:` | tears of joy | `:thinking:` | thinking |
| `:rofl:` | rolling on floor | `:pray:` | folded hands |
| `:eyes:` | eyes | `:skull:` | skull |
| `:rocket:` | rocket | `:check:` | check mark |
| `:sunglasses:` | sunglasses | `:wink:` | wink |
| `:clap:` | clap | `:muscle:` | flexed bicep |

Unrecognized 4-byte emoji appear as `[?]`. The full list of supported shortcodes is in `lua/modules/mesh/emoji.lua`.

### Authentication

Some nodes require login for full access:

```
/login mypassword      -- authenticate with the node
/logout                -- deauthenticate
```

A successful login shows the granted permission level.

---

## Debug Mode

Launch with the `-d` flag to enable debug packet logging:

```
mesh -d
mesh -d 192.168.4.1 5555
```

In debug mode:

- **All received packets** are printed with their type name and full hex dump, e.g. `[SELF_INFO] (58B): 01 03 00 ...`
- **Push notifications** are parsed into readable form: advertisements, path updates, telemetry, trace data, status responses, etc.
- **New node advertisements** are always displayed regardless of debug mode.
- **Unknown packets** are only shown in debug mode with their type code and hex dump.

Debug mode is useful for troubleshooting connectivity issues or investigating unknown protocol responses.

---

## Session Logging

Add a filename after the port to log all output to a file:

```
mesh 192.168.4.1 5555 session.log
mesh -d 192.168.4.1 5555 debug.log
```

The log file is written to `lua/modules/mesh/<filename>` in append mode. All messages displayed on screen (chat messages, system messages, errors, debug output) are written to the log. When used with `-d`, the log captures all debug packet hex dumps as well.

---

## Screen Layout

```
+------------------------------------------------------+
| NodeName | connected | Batt: 3.85v                    |  <- Row 1: Status bar
| To: Steve | Mem: 180K                                 |  <- Row 2: Target/Channel
|                                                       |
| *** PicoCalc MeshCore Client                          |
| *** Connected to 192.168.4.1:5555                     |
| *** Node: MyNode                                      |
| *** 12 contacts loaded.                               |
| [Steve] hey, how's it going?                          |  <- Incoming DM
| [-> Steve] good, you?                                 |  <- Outgoing DM
| <Ch0> hello everyone                                  |  <- Channel message
|   > delivered                                         |  <- ACK confirmation
|   > heard 1 repeat                                    |  <- Repeater confirmation
|                                                       |
|------------------------------------------------------|  <- Separator
| > _                                                   |  <- Input line
+------------------------------------------------------+
```

- **Row 1** (blue): Node name, connection status, battery voltage
- **Row 2** (gray): Current DM target or channel, free memory, mode indicator
- **Message area**: Chat messages anchored to the bottom, scrollable
- **Input line**: Your typed input with cursor

---

## Commands Reference

| Command | Description |
|---------|-------------|
| `/connect [host] [port]` | Connect to a MeshCore node |
| `/disconnect` | Disconnect from the node |
| `/quit` | Exit the mesh client (also: press Esc) |
| `/contacts` | Open the contact list browser |
| `/target <name\|number>` | Set the default DM target |
| `/msg <name\|number> <text>` | Send a one-off DM to a contact |
| `/ch [index] [text]` | Send a channel message, or switch default channel |
| `/login <password>` | Authenticate with the node |
| `/logout` | Deauthenticate |
| `/battery` | Request battery status from the node |
| `/sync` | Manually fetch any pending messages |
| `/clear` | Clear the message buffer |
| `/help [command]` | Show available commands or help for a specific command |

---

## Keyboard Shortcuts

### Chat Mode

| Key | Action |
|-----|--------|
| **Enter** | Send message / execute command |
| **Esc** | Exit the client |
| **Up / Down** | Navigate input history |
| **Shift+Up / Shift+Down** | Scroll message area |
| **Page Up / Page Down** | Scroll message area (10 lines) |
| **Left / Right** | Move cursor in input |
| **Home / End** | Jump to start / end of input |
| **Backspace / Delete** | Delete character |

### Contact List Mode

| Key | Action |
|-----|--------|
| **Up / Down** | Navigate contact list |
| **Page Up / Page Down** | Scroll contact list quickly |
| **Home / End** | Jump to first / last contact |
| **Enter** | Select contact as DM target |
| **Esc** | Return to chat view |

---

## Message Types

Messages are color-coded in the chat view:

| Type | Color | Prefix | Description |
|------|-------|--------|-------------|
| Incoming DM | Light Blue | `[sender]` | Direct message received |
| Outgoing DM | White | `[-> contact]` | Direct message you sent |
| Channel In | Lime | `<Ch0>` | Channel message received |
| Channel Out | Green | `<Ch0>` | Channel message you sent |
| System | Cyan | `***` | Status and info messages |
| Error | Red | `!!!` | Error messages |
| ACK | Yellow | `  >` | Delivery confirmations and repeat counts |

---

## Protocol Overview

The client communicates with the MeshCore node using a binary TCP protocol:

- **Outbound frames**: `0x3C` + 2-byte little-endian size + payload (max 300 bytes)
- **Inbound frames**: `0x3E` + 2-byte little-endian size + payload (max 300 bytes)

On connect, the client sends an `APP_START` command identifying itself as a MeshCore CLI client. The node responds with `SELF_INFO` containing the node name, public key, radio configuration, and location.

The client then requests the device time (for message timestamps), the contact list, and battery status. After contacts load, it begins syncing any pending messages. Incoming messages are automatically fetched when the node signals `MESSAGES_WAITING`.

Battery voltage is polled automatically every ~30 seconds and displayed in the status bar.

The client syncs its clock from the node's device time response, with a fallback to the most recent contact `lastmod` timestamp. This is necessary because the PicoCalc has no RTC clock.

---

## Tips and Best Practices

1. **Connect to Wi-Fi first** - Ensure your PicoCalc is connected to the radio node's Wi-Fi network before launching the mesh client. Most MeshCore nodes run an AP at `192.168.4.1`.

2. **Use /contacts to select targets** - The contact browser is the easiest way to pick a DM recipient. Partial name matching with `/target` is also convenient.

3. **Watch the battery** - The status bar shows your radio node's battery voltage. Keep an eye on it during extended use.

4. **Message delivery** - After sending a DM, you'll see a `sent (waiting for ack)` message. When the recipient's node acknowledges receipt, you'll see `delivered`. Mesh delivery can take seconds to minutes depending on the network. Channel messages show `sent` and then `heard N repeat(s)` as repeaters forward the message.

5. **Channel 0** - Channel 0 is the default broadcast channel on most MeshCore networks. Use it for general communication.

6. **Memory** - The client keeps the last 40 messages and up to 50 contacts in memory. Free memory is shown in the status bar. If memory gets low, use `/clear` to free the message buffer.

7. **Reconnecting** - If the connection drops (node reboots, Wi-Fi hiccup), use `/connect` to reconnect. The client will re-fetch contacts and pending messages automatically.

8. **Login** - Some node features (like accessing certain contacts or sending messages through repeaters) may require authentication. Use `/login <password>` with the password configured on your node.

9. **Emoji** - Type `:shortcode:` names in your messages to send emoji that display correctly on mobile apps. Incoming emoji are automatically converted to readable shortcode text.

10. **Logging** - Use the log file option to capture a session for later review. Combine with `-d` for full protocol-level debugging: `mesh -d 192.168.4.1 5555 debug.log`.
