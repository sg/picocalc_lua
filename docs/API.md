# Introduction <!-- omit in toc -->

This API has been in part influenced by the [CC:Tweaked](https://tweaked.cc/) API in order to facilitate porting of existing software.

- [`sys` - System functions](#sys---system-functions)
	- [`freeMemory()`](#freememory)
	- [`totalMemory()`](#totalmemory)
	- [`reset()`](#reset)
	- [`bootsel()`](#bootsel)
	- [`setOutput(pin, dir)`](#setoutputpin-dir)
	- [`getPin(pin)`](#getpinpin)
	- [`setPin(pin, state)`](#setpinpin-state)
	- [`battery()`](#battery)
	- [`getClock()`](#getclock)
	- [`setClock(speed)`](#setclockspeed)
	- [`repeatTimer(interval, callback)`](#repeattimerinterval-callback)
	- [`stopTimer()`](#stoptimer)
- [`keys` - Keyboard handling functions](#keys---keyboard-handling-functions)
	- [`poll()`](#poll)
	- [`peek()`](#peek)
	- [`wait([nomod], [onlypressed])`](#waitnomod-onlypressed)
	- [`flush()`](#flush)
	- [`getState(code)`](#getstatecode)
	- [`isAvailable([nomod], [onlypressed])`](#isavailablenomod-onlypressed)
	- [`isPrintable(char)`](#isprintablechar)
	- [Constants](#constants)
		- [`states`](#states)
		- [`modifiers`](#modifiers)
- [`fs` - Filesystem](#fs---filesystem)
	- [`open(path, mode)`](#openpath-mode)
	- [`list(path)`](#listpath)
	- [`makeDir(path)`](#makedirpath)
	- [`getSize(path)`](#getsizepath)
	- [`isDir(path)`](#isdirpath)
	- [`isReadOnly(path)`](#isreadonlypath)
	- [`attributes(path)`](#attributespath)
	- [`exists(path)`](#existspath)
	- [`delete(path)`](#deletepath)
	- [`move(source, target)`](#movesource-target)
	- [`copy(source, target)`](#copysource-target)
	- [`getFreeSpace(path)`](#getfreespacepath)
	- [`FileHandle:read([size])`](#filehandlereadsize)
	- [`FileHandle:readAll()`](#filehandlereadall)
	- [`FileHandle:readLine()`](#filehandlereadline)
	- [`FileHandle:seek([whence, [offset]])`](#filehandleseekwhence-offset)
	- [`FileHandle:write(bytes)`](#filehandlewritebytes)
	- [`FileHandle:writeLine(bytes)`](#filehandlewritelinebytes)
	- [`FileHandle:flush()`](#filehandleflush)
	- [`FileHandle:close()`](#filehandleclose)
- [`term` - Text terminal functions](#term---text-terminal-functions)
	- [`getCursorPos()`](#getcursorpos)
	- [`setCursorPos(x, y)`](#setcursorposx-y)
	- [`getCursorBlink()`](#getcursorblink)
	- [`setCursorBlink(blink)`](#setcursorblinkblink)
	- [`getSize()`](#getsize)
	- [`clear()`](#clear)
	- [`clearLine()`](#clearline)
	- [`getTextColor()`](#gettextcolor)
	- [`setTextColor(color)`](#settextcolorcolor)
	- [`getBackgroundColor()`](#getbackgroundcolor)
	- [`setBackgroundColor(color)`](#setbackgroundcolorcolor)
	- [`read([prompt])`](#readprompt)
	- [`write(text)`](#writetext)
	- [`blit(text, fg, bg)`](#blittext-fg-bg)
	- [`loadFont(filename)`](#loadfontfilename)
	- [`getFont()`](#getfont)
	- [`getFontSize()`](#getfontsize)
- [`draw` - Drawing functions](#draw---drawing-functions)
	- [`text(x, y, text, [fg], [bg], [align])`](#textx-y-text-fg-bg-align)
	- [`clear()`](#clear-1)
	- [`point(x, y, color)`](#pointx-y-color)
	- [`rect(x, y, width, height, color)`](#rectx-y-width-height-color)
	- [`rectFill(x, y, width, height, color)`](#rectfillx-y-width-height-color)
	- [`line(x1, y1, x2, y2, color)`](#linex1-y1-x2-y2-color)
	- [`circle(x, y, radius, color)`](#circlex-y-radius-color)
	- [`circleFill(x, y, radius, color)`](#circlefillx-y-radius-color)
	- [`polygon(points, color)`](#polygonpoints-color)
	- [`polygonFill(points, color)`](#polygonfillpoints-color)
	- [`triangle(c1, x1, y1, c2, x2, y2, c3, x3, y3)`](#trianglec1-x1-y1-c2-x2-y2-c3-x3-y3)
	- [`enableBuffer(mode, [dirty])`](#enablebuffermode-dirty)
	- [`blitBuffer()`](#blitbuffer)
	- [`loadBMPSprites(filename, [width], [height], [mask])`](#loadbmpspritesfilename-width-height-mask)
	- [`loadSprites(filename)`](#loadspritesfilename)
	- [`newSprites([width], [height], [count], [mask])`](#newspriteswidth-height-count-mask)
	- [`Spritesheet:blit(x, y, [id], [flip])`](#spritesheetblitx-y-id-flip)
	- [`Spritesheet:getSize()`](#spritesheetgetsize)
	- [`Spritesheet:getPixel(x, y, [id])`](#spritesheetgetpixelx-y-id)
	- [`Spritesheet:setPixel(x, y, [id])`](#spritesheetsetpixelx-y-id)
	- [`Spritesheet:getMask()`](#spritesheetgetmask)
	- [`Spritesheet:setMask()`](#spritesheetsetmask)
	- [`Spritesheet:save(filename)`](#spritesheetsavefilename)
	- [Constants](#constants-1)
- [`colors` - Color functions and constants](#colors---color-functions-and-constants)
	- [`fromRGB(R, G, B)`](#fromrgbr-g-b)
	- [`toRGB(color)`](#torgbcolor)
	- [`fromHSV(hue, saturation, value)`](#fromhsvhue-saturation-value)
	- [`toHSV(color)`](#tohsvcolor)
	- [`add(color1, color2)`](#addcolor1-color2)
	- [`subtract(color1, color2)`](#subtractcolor1-color2)
	- [`multiply(color1, color2)`](#multiplycolor1-color2)
	- [Constants](#constants-2)
- [`sound` - Programmable Sound Generator](#sound---programmable-sound-generator)
	- [`instrument([instrument|wave], [volume], [attack], [decay], [sustain], [release], [table_mode], [table_start], [table_playrate], [table_end])`](#instrumentinstrumentwave-volume-attack-decay-sustain-release-table_mode-table_start-table_playrate-table_end)
	- [`play(channel, note, instrument)`](#playchannel-note-instrument)
	- [`playPitch(channel, pitch, instrument)`](#playpitchchannel-pitch-instrument)
	- [`off(channel)`](#offchannel)
	- [`stop(channel)`](#stopchannel)
	- [`stopAll()`](#stopall)
	- [`volume(channel, volume, [relative])`](#volumechannel-volume-relative)
	- [`pitch(channel, pitch, [relative])`](#pitchchannel-pitch-relative)
	- [`Instrument`](#instrument)
	- [Constants](#constants-3)
		- [`presets`](#presets)
		- [`drums`](#drums)
		- [`tableModes`](#tablemodes)
- [`wifi` - Wi-Fi networking](#wifi---wi-fi-networking)
        - [`init([country])`](#initcountry)
        - [`isInitialized()`](#isinitialized)
        - [`scan()`](#scan)
        - [`connect(ssid, password, [auth], [timeout])`](#connectssid-password-auth-timeout)
        - [`disconnect()`](#disconnect)
        - [`status()`](#status)
        - [`isConnected()`](#isconnected)
        - [`getIP()`](#getip)
        - [`getGateway()`](#getgateway)
        - [`getNetmask()`](#getnetmask)
        - [`getInfo()`](#getinfo)
        - [Constants](#constants-4)
                - [Authentication Modes](#authentication-modes)
                - [Status Codes](#status-codes)
- [`socket` - TCP/UDP/TLS sockets](#socket---tcpudptls-sockets)
        - [`tcp()`](#tcp)
        - [`udp()`](#udp)
        - [`tls()`](#tls)
        - [`dns.resolve(hostname)`](#dnsresolvehostname)
    - [`ping(hostname, timeout)`](#ping)
        - [`Socket:connect(host, port, [timeout])`](#socketconnecthost-port-timeout)
        - [`Socket:send(data)`](#socketsenddata)
        - [`Socket:receive([size], [timeout])`](#socketreceivesize-timeout)
        - [`Socket:close()`](#socketclose)
        - [`Socket:settimeout(seconds)`](#socketsettimeoutseconds)
        - [`Socket:available()`](#socketavailable)
        - [`Socket:isconnected()`](#socketisconnected)
        - [`Socket:bind(port, [address])`](#socketbindport-address)
        - [`Socket:listen([backlog])`](#socketlistenbacklog)
        - [`Socket:accept([timeout])`](#socketaccepttimeout)
        - [`Socket:sendto(data, host, port)`](#socketsendtodata-host-port)
        - [`Socket:receivefrom([size], [timeout])`](#socketreceivefromsize-timeout)
        - [TLS Socket Methods](#tls-socket-methods)
        - [Constants](#constants-5)
- [`http` - HTTP client (Lua library)](#http---http-client-lua-library)
        - [`http.request(url, [options])`](#httprequesturl-options)
        - [`http.get(url, [options])`](#httpgeturl-options)
        - [`http.post(url, body, [content_type], [options])`](#httpposturl-body-content_type-options)
        - [`http.urlencode(str)`](#httpurlencodestr)
        - [`http.encode_params(params)`](#httpencode_paramsparams)


# `sys` - System functions

## `freeMemory()`
Returns the amount of unused memory

**Returns**
1. `number` - Amount of memory in bytes

## `totalMemory()`
Returns the amount of total system memory

**Returns**
1. `number` - Amount of memory in bytes

## `reset()`
Resets the Pico

## `bootsel()`
Resets the Pico in BOOTSEL mode

## `setOutput(pin, dir)`
Sets a GPIO pin as output or input

**Parameters**
1. `pin : number` - The desired GPIO pin
2. `dir : boolean` - True for output, false for input

## `getPin(pin)`
Gets the current state of an input pin

**Parameters**
1. `pin : number` - The desired GPIO pin

**Returns**
1. `boolean` - False for low, true for high

## `setPin(pin, state)`
Sets the output of a pin

**Parameters**
1. `pin : number` - The desired GPIO pin
2. `state : boolean` - False for low, true for high

## `battery()`
Gets the current state of charge of the battery

**Returns**
1. `number` - The battery state in 0-100 percentage
2. `boolean` - Whether or not the charger is connected

## `getClock()`
Gets the current CPU clock speed

**Returns**
1. `number` - Current clock speed in MHz

## `setClock(speed)`
Sets the CPU clock speed

**Parameters**
1. `speed : number` - The desired clock speed in MHz

**Returns**
1. `boolean` - Whether or not the CPU clock was able to be set

## `repeatTimer(interval, callback)`
Sets up a repeating timer to run a Lua function. Only one timer can be set at a time and calling this function will cancel the previous timer if one was set

**Parameters**
1. `interval : number` - The interval in milliseconds to run the timer at. Positive values means time between each function execution (end to start), negative values means time between each function call (start to start)
2. `callback : function` - The Lua function to execute when the timer fires

## `stopTimer()`
Stops an existing repeating timer


# `keys` - Keyboard handling functions

## `poll()`
Returns latest keyboard event without blocking, clearing it from the queue

**Returns**
1. `number` - One of `keys.states`
2. `number` - Bitfield maskable by `keys.modifiers`
3. `string` - Key code or character, 0 if no key was pressed

## `peek()`
Same as `poll()` but does not clear it from the queue

**Returns**
1. `number` - One of `keys.states`
2. `number` - Bitfield maskable by `keys.modifiers`
3. `string` - Key code or character, 0 if no key was pressed

## `wait([nomod], [onlypressed])`
Same as `poll()` but halts execution until a key is pressed

**Parameters**
1. `nomod : boolean` - Ignore key events from modifier keys, default false
2. `onlypressed : boolean` - Ignore key events other than `keys.state.pressed`, default true

**Returns**
1. `number` - One of `keys.state`
2. `number` - Bitfield maskable by `keys.modifiers`
3. `string` - Key code or character

## `flush()`
Discard all unused keyboard buffer

## `getState(code)`
Checks if a specific key is currently pressed

**Parameters**
1. `code : string` - One of `keys` constants, or key code

**Returns**
1. `boolean` - True if the key is currently held down, false otherwise

## `isAvailable([nomod], [onlypressed])`
Checks if there are key events available to be polled without blocking. Will swallow events to be ignored if specified

**Parameters**
1. `nomod : boolean` - Ignore key events from modifier keys, default false
2. `onlypressed : boolean` - Ignore key events other than `keys.state.pressed`, default true

**Returns**
1. `boolean` - Whether or not there are key events available

## `isPrintable(char)`
Checks if a character is an ASCII printable character

**Returns**
1. `boolean` - Whether or not the character is printable


## Constants

* `alt`
* `leftShift`
* `rightShift`
* `control`
* `esc`
* `left`
* `up`
* `down`
* `right`
* `backspace`
* `enter`
* `capslock`
* `pause`
* `home`
* `delete`
* `end`
* `pageUp`
* `pageDown`
* `tab`

### `states`

* `idle`
* `pressed`
* `released`
* `hold`
* `longHold`

### `modifiers`

* `control`
* `alt`
* `shift`
* `leftShift`
* `rightShift`


# `fs` - Filesystem

## `open(path, mode)`
Opens a file for usage

**Parameters**
1. `path : string` - Path to the file
2. `mode : string` - Same modes as standard libc `fopen()`

**Returns**
1. `FileHandle` - Object for file operations, throws error if unable to open

## `list(path)`
List the contents of a directory, throws error if unable to read or not a directory

**Parameters**
1. `path : string` - Path to search in

**Returns**
1. `table` - Nested table of entries inside search path
   1. `name : string` - Filename
   2. `size : number` - File size
   3. `isDir : boolean` - Whether entry is a directory

## `makeDir(path)`
Create directory at specified path. Does not create recursively

**Parameters**
1. `path : string` - Path of directory to be created

## `getSize(path)`
Returns the size of a file

**Parameters**
1. `path : string` - Path to the file

**Returns**
1. `number` - Size of the file in bytes

## `isDir(path)`
Checks if a path is a directory

**Parameters**
1. `path : string` - Path to be checked

**Returns**
1. `boolean` - Whether or not path is a directory

## `isReadOnly(path)`
Checks if a path is a read-only

**Parameters**
1. `path : string` - Path to be checked

**Returns**
1. `boolean` - Whether or not path is read-only

## `attributes(path)`
Returns a list of attributes for a path

**Parameters**
1. `path : string` - Path to be checked

**Returns**
1. `table`:
    * `size : number` - Size of the file in bytes
    * `isDir : boolean` - Whether path is a directory
    * `isReadOnly : boolean` - Whether path is a read-only
    * `date : number` - Date, as recorded by pico_fatfs
    * `time : number` - Time, as recorded by pico_fatfs

## `exists(path)`
Returns whether or not the path exists

**Parameters**
1. `path : string` - Path to be checked

**Returns**
1. `boolean` - Whether or not path exists

## `delete(path)`
Deletes the specified path from disk

**Parameters**
1. `path : string` - Path to be deleted

## `move(source, target)`
Moves a path to another, can be used to rename files

**Parameters**
1. `source : string` - Path to be moved
2. `target : string` - Destination of the new path

## `copy(source, target)`
Copies a file to another, does not work on directories

**Parameters**
1. `source : string` - File to be copied
2. `target : string` - Destination of the new file

## `getFreeSpace(path)`
Gets the available disk space

**Parameters**
1. `path : string` - Path to be checked, if ommitted uses "" for the root folder

**Returns**
1. `number` - The available free space in clusters
2. `number` - The total disk size in clusters

## `FileHandle:read([size])`
Reads an amount of bytes from an open file

**Parameters**
1. `size : number` - The amount of bytes to be read from the file, defaults to 1

**Returns**
1. `string | nil` - The bytes read from the file, nil if none available (end of file)

## `FileHandle:readAll()`
Reads the entire open file into a string

**Returns**
1. `string | nil` - The file contents, nil if nothing available to read

## `FileHandle:readLine()`
Reads the open file until the next newline character. Does not return the newline

**Returns**
1. `string | nil` - The line read, nil if nothing available to read

## `FileHandle:seek([whence, [offset]])`
Seek to a new position within the file. The new position is an offset given by offset, relative to a start position determined by `whence`:

* `"set"`: `offset` is relative to the beginning of the file.
* `"cur"`: Relative to the current position. This is the default.
* `"end"`: Relative to the end of the file.

**Parameters**
1. `whence : string` - Where the offset is relative to
2. `offset : number` - The offset to seek to

**Returns**
1. `number` - The new position in the file

## `FileHandle:write(bytes)`
Writes a string of bytes to an open file

**Parameters**
1. `bytes : string` - The bytes to be written

**Returns**
1. `number` - The number of bytes successfully written

## `FileHandle:writeLine(bytes)`
Same as `write(bytes)`, but adds a newline character at the end of the string written

**Parameters**
1. `bytes : string` - The bytes to be written

**Returns**
1. `number` - The number of bytes successfully written

## `FileHandle:flush()`
Commits an open file's written data to disk without closing it

## `FileHandle:close()`
Closes an open file


# `term` - Text terminal functions

## `getCursorPos()`
Gets the current terminal cursor position

**Returns**
1. `number` - The horizontal cursor position in characters
2. `number` - The vertical cursor position in characters

## `setCursorPos(x, y)`
Sets the terminal cursor position, starting at (1, 1) for top left

**Parameters**
1. `x : number` - The horizontal cursor position in characters
2. `y : number` - The vertical cursor position in characters

## `getCursorBlink()`
Gets whether the terminal cursor currently blinks

**Returns**
1. `boolean` - Whether or not the cursor blink is active

## `setCursorBlink(blink)`
Sets the terminal cursor blinking

**Parameters**
1. `blink : boolean` - Whether or not the cursor blink should be active

## `getSize()`
Gets the terminal size

**Returns**
1. `number` - The terminal width in characters
2. `number` - The terminal height in characters

## `clear()`
Clears the entire terminal and resets cursor to position (0, 0)

## `clearLine()`
Clears the line indicated by the current cursor position

## `getTextColor()`
Returns the foreground color the text will currently be written in

**Returns**
1. `number` - The [`color`](#colors---color-functions-and-constants) in a 16-bit format

## `setTextColor(color)`
Sets the foreground color for the text to be written in

**Parameters**
1. `color : number` - The [`color`](#colors---color-functions-and-constants) in a 16-bit format

## `getBackgroundColor()`
Returns the background color the text will currently be written in

**Returns**
1. `number` - The [`color`](#colors---color-functions-and-constants) in a 16-bit format

## `setBackgroundColor(color)`
Sets the background color for the text to be written in

**Parameters**
1. `color : number` - The [`color`](#colors---color-functions-and-constants) in a 16-bit format

## `read([prompt])`
Produces a prompt for user text entry which echoes to the screen, waiting until the Enter key is pressed

**Parameters**
1. `prompt : string` - An optional prompt to be shown where the user enters text

**Returns**
1. `string` - The user's input

## `write(text)`
Writes text to the terminal screen at the current cursor position with the current text colors, updating the cursor position to the end of the text. Unlike `print()`, does not automatically line break at the end

**Parameters**
1. `text : string` - The text to be written

## `blit(text, fg, bg)`
Similar to `write(text)` but controlling the foreground and background colors per-character. In case the color strings are shorter than the text string, they will repeat back from the start

**Parameters**
1. `text : string` - The text to be written
2. `fg : string` - A string of hexadecimal values `0` to `f` matching ANSI colors for the foreground color
3. `bg : string` - A string of hexadecimal values `0` to `f` matching ANSI colors for the background color

## `loadFont(filename)`
Loads a font from the SD card, falling back to the default built-in font in case of failure.

**Parameters**
1. `filename : string` - The filename on SD card of the font to load

**Returns**
1. `boolean` - Whether or not loading the font was successful

## `getFont()`
Checks which font file is currently being used by the terminal

**Returns**
1. `string | nil` - The filename of the font, nil if no font is loaded and the terminal is using the built-in default

## `getFontSize()`
Returns the size of each glyph of the font currently being used by the terminal

**Returns**
1. `number` - The width of each glyph in pixels
2. `number` - The height of each glyph in pixels


# `draw` - Drawing functions

## `text(x, y, text, [fg], [bg], [align])`
Draws text on the screen at a determined position with determined colors

**Parameters**
1. `x : number` - The horizontal position in pixels
2. `y : number` - The vertical position in pixels
3. `text : string` - The text to be written
4. `fg : number` - The foreground [`color`](#colors---color-functions-and-constants), defaults to white
5. `bg : number` - The background [`color`](#colors---color-functions-and-constants), defaults to black
6. `align : number` - Which way to align text, see [Constants](#constants-1). Defaults to `align_left`

## `clear()`
Clears the drawn screen. This does not affect the terminal cursor

## `point(x, y, color)`
Draws a single pixel on the screen

**Parameters**
1. `x : number` - The horizontal position in pixels
2. `y : number` - The vertical position in pixels
3. `color : number` - The [`color`](#colors---color-functions-and-constants) to be drawn

## `rect(x, y, width, height, color)`
Draws the outline of a rectangle on the screen

**Parameters**
1. `x : number` - The horizontal position of the top left corner in pixels
2. `y : number` - The vertical position of the top left corner in pixels
3. `width : number` - The width in pixels
4. `height : number` - The height in pixels
5. `color : number` - The [`color`](#colors---color-functions-and-constants) to be drawn

## `rectFill(x, y, width, height, color)`
Draws a filled rectangle on the screen

**Parameters**
1. `x : number` - The horizontal position of the top left corner in pixels
2. `y : number` - The vertical position of the top left corner in pixels
3. `width : number` - The width in pixels
4. `height : number` - The height in pixels
5. `color : number` - The [`color`](#colors---color-functions-and-constants) to be drawn

## `line(x1, y1, x2, y2, color)`
Draws a line between two points on the screen

**Parameters**
1. `x1 : number` - The horizontal position of the first point in pixels
2. `y1 : number` - The vertical position of the first point in pixels
3. `x2 : number` - The horizontal position of the second point in pixels
4. `y2 : number` - The vertical position of the second point in pixels
5. `color : number` - The [`color`](#colors---color-functions-and-constants) to be drawn

## `circle(x, y, radius, color)`
Draws the outline of a circle on the screen

**Parameters**
1. `x : number` - The horizontal position of the center of the circle in pixels
2. `y : number` - The vertical position of the center of the circle in pixels
3. `radius : number` - The radius of the circle in pixels
4. `color : number` - The [`color`](#colors---color-functions-and-constants) to be drawn

## `circleFill(x, y, radius, color)`
Draws a filled circle on the screen

**Parameters**
1. `x : number` - The horizontal position of the center of the circle in pixels
2. `y : number` - The vertical position of the center of the circle in pixels
3. `radius : number` - The radius of the circle in pixels
4. `color : number` - The [`color`](#colors---color-functions-and-constants) to be drawn

## `polygon(points, color)`
Draws the outline of a polygon to the screen

**Parameters**
1. `points : table` - A sequence of coordinates for the polygon's points. The table must have an even number of values, each pair of values representing the horizontal and the vertical positions in pixels of each point respectively
2. `color : number` - The [`color`](#colors---color-functions-and-constants) to be drawn

## `polygonFill(points, color)`
Draws a filled polygon to the screen

**Parameters**
1. `points : table` - A sequence of coordinates for the polygon's points. The table must have an even number of values, each pair of values representing the horizontal and the vertical positions in pixels of each point respectively
2. `color : number` - The [`color`](#colors---color-functions-and-constants) to be drawn

## `triangle(c1, x1, y1, c2, x2, y2, c3, x3, y3)`
Draw a triangle with each vertex shaded by a different color

**Parameters**
1. `c1 : number` - The [`color`](#colors---color-functions-and-constants) to shade the first vertex
2. `x1 : number` - The horizontal position of the first vertex in pixels
3. `y1 : number` - The vertical position of the first vertex in pixels
1. `c2 : number` - The [`color`](#colors---color-functions-and-constants) to shade the second vertex
2. `x2 : number` - The horizontal position of the second vertex in pixels
3. `y2 : number` - The vertical position of the second vertex in pixels
1. `c3 : number` - The [`color`](#colors---color-functions-and-constants) to shade the third vertex
2. `x3 : number` - The horizontal position of the third vertex in pixels
3. `y3 : number` - The vertical position of the third vertex in pixels

## `enableBuffer(mode, [dirty])`
Enables or disables a framebuffer mode. While the framebuffer is enabled, no drawing functions will be reflected on the screen until the framebuffer is blitted, or the framebuffer is disabled. Valid mode values:
- `0`: Direct LCD drawing (disable framebuffer)
- `1`: PSRAM, slower access but does not use system RAM
- `2`: RAM, faster than PSRAM but with lower color depth (RGB565 is converted to RGB233 automatically) and uses ~100KB of RAM

The RAM framebuffer is dynamically allocated when enabled and freed when disabled.

**Parameters**
1. `mode : integer | boolean` - The framebuffer mode to enable, boolean values are accepted for enabling PSRAM (legacy)

**Returns**
1. `boolean` - Whether or not setting the mode was successful

## `blitBuffer()`
Blit the contents of the framebuffer to the screen

## `loadBMPSprites(filename, [width], [height], [mask])`
Loads a spritesheet to memory for blitting sprites to the screen. Formats supported are 24bit and 32bit BMP, sprites are indexed top left to bottom right as an atlas

**Parameters**
1. `filename : string` - The path for the BMP on disk to be loaded
2. `width : number` - The width of each individual sprite, defaults to the entire width of the image if omitted
3. `height : number` - The height of each individual sprite, defaults to the entire width of the image if omitted
4. `mask : number` - The [`color`](#colors---color-functions-and-constants) to be used as transparent pixels for the sprites. Defaults to `RGB(255, 0, 255)`

**Returns**
1. `spritesheet` - Spritesheet object

## `loadSprites(filename)`
Loads a spritesheet to memory as saved by `Spritesheet:save`

**Parameters**
1. `filename : string` - The path for the Spritesheet on disk to be loaded

**Returns**
1. `spritesheet` - Spritesheet object

## `newSprites([width], [height], [count], [mask])`
Loads a spritesheet to memory for blitting sprites to the screen. Formats supported are 24bit and 32bit BMP, sprites are indexed top left to bottom right as an atlas

**Parameters**
1. `filename : string` - The path for the BMP on disk to be loaded
2. `width : number` - The width of each individual sprite, defaults to 16
3. `height : number` - The height of each individual sprite, defaults to 16
4. `height : number` - The number of sprites in the sheet, defaults to 1
5. `mask : number` - The [`color`](#colors---color-functions-and-constants) to be used as transparent pixels for the sprites. Defaults to `RGB(255, 0, 255)`

**Returns**
1. `spritesheet` - Spritesheet object

## `Spritesheet:blit(x, y, [id], [flip])`
Blits a sprite from a spritesheet onto the screen

**Parameters**
1. `x : number` - The horizontal position on the screen to blit the sprite to
2. `y : number` - The vertical position on the screen to blit the sprite to
3. `id : number` - The index of the desired sprite within the spritesheet, defaults to 0
4. `flip : number` - Bitmask for drawing the sprite flipped, see [Constants](#constants-1)

## `Spritesheet:getSize()`
Returns the sizes of the spritesheet

**Returns**
1. `number` - The width of each individual sprite
2. `number` - The height of each individual sprite
3. `number` - How many sprites are in the sheet

## `Spritesheet:getPixel(x, y, [id])`
Reads the color of a pixel in a sprite

**Parameters**
1. `x : number` - The horizontal position of the pixel to read
2. `y : number` - The vertical position of the pixel to read
3. `id : number` - The index of the desired sprite within the spritesheet, defaults to 0

**Returns**
1. `number` - The [`color`](#colors---color-functions-and-constants) of the pixel

## `Spritesheet:setPixel(x, y, [id])`
Writes the color of a pixel in a sprite

**Parameters**
1. `x : number` - The horizontal position of the pixel to read
2. `y : number` - The vertical position of the pixel to read
3. `mask : number` - The [`color`](#colors---color-functions-and-constants) to write onto the pixel
4. `id : number` - The index of the desired sprite within the spritesheet, defaults to 0

## `Spritesheet:getMask()`
Gets the mask color used for sprite transparency in a sheet

**Returns**
1. `number` - The [`color`](#colors---color-functions-and-constants) used as transparency

## `Spritesheet:setMask()`
Sets the mask color used for sprite transparency in a sheet

**Parameters**
1. `mask : number` - The [`color`](#colors---color-functions-and-constants) to be used as transparency

## `Spritesheet:save(filename)`
Saves a spritesheet from memory onto disk

**Parameters**
1. `filename : string` - The path for the file to be saved on disk

## Constants

* `flip_horizontal`
* `flip_vertical`
* `flip_both`
* `align_left`
* `align_center`
* `align_right`


# `colors` - Color functions and constants

## `fromRGB(R, G, B)`
Convert RGB values into a 16-bit color value

**Parameters**
1. `R : number` - The input color's red value from 0 to 255
2. `G : number` - The input color's green value from 0 to 255
3. `B : number` - The input color's blue value from 0 to 255

**Returns**
1. `number` - The resulting 16-bit color value

## `toRGB(color)`
Convert a 16-bit color vaalue into RGB values

**Parameters**
1. `color : number` - The input 16-bit color value

**Returns**
1. `number` - The resulting red value from 0 to 255
2. `number` - The resulting green value from 0 to 255
3. `number` - The resulting blue value from 0 to 255

## `fromHSV(hue, saturation, value)`
Convert HSV values into a 16-bit color value

**Parameters**
1. `hue : number` - The input color's hue from 0 to 255
2. `saturation : number` - The input color's saturation from 0 to 255
3. `value : number` - The input color's value (brightness) from 0 to 255

**Returns**
1. `number` - The resulting 16-bit color value

## `toHSV(color)`
Convert a 16-bit color vaalue into HSV values

**Parameters**
1. `color : number` - The input 16-bit color value

**Returns**
1. `number` - The resulting hue from 0 to 255
2. `number` - The resulting saturation from 0 to 255
3. `number` - The resulting value (brightness) from 0 to 255

## `add(color1, color2)`
Add two 16-bit colors together

**Parameters**
1. `color1 : number` - The first 16-bit color to add
2. `color2 : number` - The second 16-bit color to add

**Returns**
1. `number` - The resulting 16-bit color from the addition

## `subtract(color1, color2)`
Subtract two 16-bit colors

**Parameters**
1. `color1 : number` - The 16-bit color to subtract from
2. `color2 : number` - The 16-bit color to be subtracted

**Returns**
1. `number` - The resulting 16-bit color from the subtraction

## `multiply(color1, color2)`
Multiply two 16-bit colors together

**Parameters**
1. `color1 : number` - The first 16-bit color to multiply
2. `color2 : number` - The second 16-bit color to multiply

**Returns**
1. `number` - The resulting 16-bit color from the multiplication

## Constants

* `white`
* `orange`
* `magenta`
* `lightBlue`
* `yellow`
* `lime`
* `pink`
* `gray`
* `lightGray`
* `cyan`
* `purple`
* `blue`
* `brown`
* `green`
* `red`
* `black`


# `sound` - Programmable Sound Generator

## `instrument([instrument|wave], [volume], [attack], [decay], [sustain], [release], [table_mode], [table_start], [table_playrate], [table_end])`
Create or clone an instrument object to be used to play sounds

**Parameters**
1. `instrument | wave : integer` - The wave sample number to assign to the instrument. If an `Instrument` object is passed instead, all other parameters are ignored and a clone of that instrument is returned. Defaults to 0 (pulse-width wavetable)
2. `volume : number` - Overall instrument volume 0.0-1.0. Defaults to 1.0
3. `attack : integer` - ADSR envelope attack value in milliseconds. Defaults to 0
4. `decay : integer` - ADSR envelope decay value in milliseconds. Defaults to 1000
5. `sustain : number` - ADSR envelope sustain value in 0.0-1.0. Defaults to 0.0
6. `release : integer` - ADSR envelope release value in milliseconds. Defaults to 0
7. `table_mode : integer` - Sets how the wavetable will be swept, see [`sound.tableModes`](#tablemodes). Defaults to `single`
8. `table_start : integer` - Wavetable slice to start sweep at. Defaults to 0
9.  `table_playrate : integer` - The number of samples to wait before advancing the wavetable sweep, lower numbers mean faster sweep, can be negative. Defaults to 500
10. `table_end : integer` - Wavetable slice to end sweep at. Defaults to last slice of the selected wavetable

**Returns**
1. `Instrument` - Userdata object of an instrument which can be played

## `play(channel, note, instrument)`
Plays a note value using a specified instrument at a specified channel

**Parameters**
1. `channel : integer` - The channel to play at. 8 channels are available at values 0-7
2. `note : integer` - The note value to pitch the instrument at. Value 36 corresponds to C-3
3. `instrument : Instrument` - The instrument to be played

## `playPitch(channel, pitch, instrument)`
Plays an absolute pitch value using a specified instrument at a specified channel

**Parameters**
1. `channel : integer` - The channel to play at. 8 channels are available at values 0-7
2. `pitch : number` - The rate at which to play the instrument or sample. 1.0 means normal playback
3. `instrument : Instrument` - The instrument to be played

## `off(channel)`
Triggers a release of an instrument currently playing on a specified channel

**Parameters**
1. `channel : integer` - The channel to trigger the release at

## `stop(channel)`
Hard stops any sound playing on a specified channel

**Parameters**
1. `channel : integer` - The channel to stop playing

## `stopAll()`
Stops all sounds playing

## `volume(channel, volume, [relative])`
Changes the volume of an instrument currently playing on a specified channel

**Parameters**
1. `channel : integer` - The currently playing channel to change
2. `volume : number` - The volume value ranging 0.0-1.0
3. `relative : boolean` - Whether the value should be added relative to the current volume or not. Defaults to false

## `pitch(channel, pitch, [relative])`
Changes the pitch of an instrument currently playing on a specified channel

**Parameters**
1. `channel : integer` - The currently playing channel to change
2. `pitch : number` - The pitch value
3. `relative : boolean` - Whether the value should be added relative to the current pitch or not. Defaults to false

## `Instrument`
Instrument objects have the following attributes which can be read and set:

- `wave : integer` - The wave sample number assigned to the instrument
- `volume : number` - Overall instrument volume in range 0.0-1.0
- `attack : integer` - ADSR envelope attack value in milliseconds
- `decay : integer` - ADSR envelope decay value in milliseconds
- `sustain : number` - ADSR envelope sustain value in range 0.0-1.0
- `release : integer` - ADSR envelope release value in milliseconds
- `table_mode : integer` - How the wavetable will be swept
- `table_start : integer` - Wavetable slice to start sweep at
-  `table_playrate : integer` - The number of samples to wait before advancing the wavetable sweep, lower numbers mean faster sweep, can be negative
-  `table_end : integer` - Wavetable slice to end sweep at

## Constants

### `presets`
- `square`
- `thin`
- `string`
- `violin`
- `voice`
- `pluck`
- `pulse`
- `warp`
- `sine`
- `triangle`

### `drums`
- `kick1`
- `kick2`
- `snare1`
- `snare2`
- `hihat`
- `tom`
- `cowbell`

### `tableModes`
- `single` - Treats the wavetable as a single sample, like drums. Playback ends once the first slice is played
- `oneShot` - Sweeps the wavetable from start to end, then stops sweep at the end
- `pingPong` - Sweeps the wavetable, switching directions whenever end or start are reached
- `loop` - Sweeps the wavetable in a single direction, resetting the sweep from the other side of the loop once the end is reached

# `wifi` - Wi-Fi networking

## `init([country])`
Initialize the Wi-Fi hardware. Must be called before any other Wi-Fi functions.

**Parameters**
1. `country : string` - Optional 2-letter country code (e.g., "US", "GB", "DE").

**Returns**
1. `boolean` - Whether initialization was successful


## `isInitialized()`
Check if Wi-Fi has been initialized

**Returns**
1. `boolean` - Whether Wi-Fi is initialized

## `scan()`
Perform a scan for available Wi-Fi networks

**Returns**
1. `table | nil` - Array of network tables, or nil on failure
   * `ssid : string` - Network name
   * `rssi : number` - Signal strength in dBm (typically -30 to -90)
   * `channel : number` - Wi-Fi channel (1-14)
   * `secure : boolean` - Whether authentication is required
   * `authMode : number` - Raw authentication mode value
   * `bssid : string` - MAC address as "XX:XX:XX:XX:XX:XX"
2. `string` - Error message if scan failed

## `connect(ssid, password, [auth], [timeout])`
Connect to a Wi-Fi network

**Parameters**
1. `ssid : string` - The network name to connect to
2. `password : string` - The network password (empty string for open networks)
3. `auth : number` - Authentication type: `wifi.AUTH_OPEN`, `wifi.AUTH_WPA2` (default), or `wifi.AUTH_WPA3`
4. `timeout : number` - Connection timeout in milliseconds, defaults to 30000

**Returns**
1. `boolean` - Whether connection was successful
2. `string` - Error message if connection failed

## `disconnect()`
Disconnect from the current Wi-Fi network

## `status()`
Get the current connection status

**Returns**
1. `number` - One of the status constants: `wifi.STATUS_DOWN`, `wifi.STATUS_JOIN`, `wifi.STATUS_NOIP`, `wifi.STATUS_UP`, `wifi.STATUS_FAIL`, `wifi.STATUS_NONET`, or `wifi.STATUS_BADAUTH`

## `isConnected()`
Check if connected to a network with an IP address

**Returns**
1. `boolean` - Whether fully connected with IP address

## `getIP()`
Get the current IP address

**Returns**
1. `string | nil` - IP address or nil if not connected

## `getGateway()`
Get the gateway IP address

**Returns**
1. `string | nil` - Gateway IP address or nil if not connected

## `getNetmask()`
Get the subnet mask

**Returns**
1. `string | nil` - Subnet mask or nil if not connected

## `getInfo()`
Get all network information as a table

**Returns**
1. `table | nil` - Network information table, or nil if not connected
   * `ip : string` - IP address
   * `ssid : string` - SSID of connected wifi network
   * `gateway : string` - Gateway address
   * `netmask : string` - Subnet mask

## Constants

### Authentication Modes

* `AUTH_OPEN` - Open network (no password)
* `AUTH_WPA2` - WPA2-PSK
* `AUTH_WPA3` - WPA3-SAE

### Status Codes

* `STATUS_DOWN` - Link down, not connected
* `STATUS_JOIN` - Associated with access point
* `STATUS_NOIP` - Connected, waiting for DHCP
* `STATUS_UP` - Fully connected with IP address
* `STATUS_FAIL` - Connection failed
* `STATUS_NONET` - Network not found
* `STATUS_BADAUTH` - Authentication failed

# `socket` - TCP/UDP/TLS sockets

The socket module provides TCP, UDP, and TLS network communication. Requires Wi-Fi to be connected first.

## `tcp()`
Create a new TCP socket

**Returns**
1. `Socket` - A new TCP socket object
2. `string` - Error message if creation failed

## `udp()`
Create a new UDP socket

**Returns**
1. `Socket` - A new UDP socket object
2. `string` - Error message if creation failed

## `tls()`
Create a new TLS socket for encrypted connections (e.g., HTTPS). Certificate verification is disabled.

**Returns**
1. `TLSSocket` - A new TLS socket object
2. `string` - Error message if creation failed

## `ping(hostname|IP, timeout)`
Send an ICMP echo request packet to host

**Parameters**
1. `hostname|IP : string` - The hostname or IP to ping
2. `timeout: int` - timeout in milliseconds

**Returns**
1. `table | nil` - A table holding the ping state fields, or nil if socket creation failed
   * `success : bool` - if a reply was recieved
   * `time : number` - milliseconds elapsed
   * `ttl : number` - time to live
   * `ip : string` - IP of host (after successful dns lookup)
2. `string` - Error message if socket creation failed

## `dns.resolve(hostname)`
Resolve a hostname to an IP address (doesn't currently support reverse loo-ups)

**Parameters**
1. `hostname : string` - The hostname to resolve

**Returns**
1. `string | nil` - The resolved IP address, or nil on failure
2. `string` - Error message if resolution failed

## `Socket:connect(host, port, [timeout])`
Connect a TCP socket to a remote host

**Parameters**
1. `host : string` - The hostname or IP address to connect to
2. `port : number` - The port number (1-65535)
3. `timeout : number` - Connection timeout in milliseconds, defaults to 30000

**Returns**
1. `boolean` - Whether connection was successful
2. `string` - Error message if connection failed

## `Socket:send(data)`
Send data through a connected socket

**Parameters**
1. `data : string` - The data to send

**Returns**
1. `number | nil` - Number of bytes sent, or nil on error
2. `string` - Error message if send failed

## `Socket:receive([size], [timeout])`
Receive data from a connected socket

**Parameters**
1. `size : number` - Maximum bytes to receive, defaults to 1024 (max 8192)
2. `timeout : number` - Receive timeout in milliseconds

**Returns**
1. `string | nil` - The received data, or nil on error/timeout
2. `string` - Error message if receive failed

## `Socket:close()`
Close the socket and free resources

## `Socket:settimeout(seconds)`
Set the default timeout for socket operations

**Parameters**
1. `seconds : number` - Timeout in seconds (0 for blocking)

## `Socket:available()`
Check how many bytes are available to read without blocking

**Returns**
1. `number` - Number of bytes available in the receive buffer

## `Socket:isconnected()`
Check if the socket is currently connected

**Returns**
1. `boolean` - Whether the socket is connected

## `Socket:bind(port, [address])`
Bind a socket to a local port (for servers or UDP)

**Parameters**
1. `port : number` - The port number to bind to (1-65535)
2. `address : string` - Local address to bind to, defaults to all interfaces

**Returns**
1. `boolean` - Whether bind was successful
2. `string` - Error message if bind failed

## `Socket:listen([backlog])`
Start listening for incoming TCP connections

**Parameters**
1. `backlog : number` - Maximum pending connections, defaults to 5

**Returns**
1. `boolean` - Whether listen was successful
2. `string` - Error message if listen failed

## `Socket:accept([timeout])`
Accept an incoming TCP connection

**Parameters**
1. `timeout : number` - Accept timeout in milliseconds (0 for blocking)

**Returns**
1. `Socket | nil` - New socket for the client connection, or nil on timeout/error
2. `string` - Error message if accept failed

## `Socket:sendto(data, host, port)`
Send a UDP datagram to a specific address

**Parameters**
1. `data : string` - The data to send
2. `host : string` - Destination hostname or IP address
3. `port : number` - Destination port number (1-65535)

**Returns**
1. `number | nil` - Number of bytes sent, or nil on error
2. `string` - Error message if send failed

## `Socket:receivefrom([size], [timeout])`
Receive a UDP datagram and get sender information

**Parameters**
1. `size : number` - Maximum bytes to receive, defaults to 1024 (max 8192)
2. `timeout : number` - Receive timeout in milliseconds

**Returns**
1. `string | nil` - The received data, or nil on error/timeout
2. `string` - Sender IP address (or error message on failure)
3. `number` - Sender port number

## TLS Socket Methods

TLS sockets support a subset of the regular socket methods, designed for HTTPS client connections.

### `TLSSocket:connect(host, port, [timeout])`
Connect to a server with TLS encryption (blocking, includes TLS handshake)

**Parameters**
1. `host : string` - The hostname or IP address to connect to
2. `port : number` - The port number (typically 443 for HTTPS)
3. `timeout : number` - Connection timeout in milliseconds, defaults to 30000

**Returns**
1. `boolean` - Whether connection and TLS handshake succeeded
2. `string` - Error message if connection failed

### `TLSSocket:send(data)`
Send data through the encrypted connection

**Parameters**
1. `data : string` - The data to send

**Returns**
1. `number | nil` - Number of bytes sent, or nil on error
2. `string` - Error message if send failed

### `TLSSocket:receive([size], [timeout])`
Receive data from the encrypted connection

**Parameters**
1. `size : number` - Maximum bytes to receive, defaults to 1024 (max 8192)
2. `timeout : number` - Receive timeout in milliseconds

**Returns**
1. `string | nil` - The received data, or nil on error/timeout
2. `string` - Error message if receive failed

### `TLSSocket:close()`
Close the TLS connection and free resources

### `TLSSocket:settimeout(seconds)`
Set the default timeout for operations

**Parameters**
1. `seconds : number` - Timeout in seconds

### `TLSSocket:available()`
Check how many bytes are available to read

**Returns**
1. `number` - Number of bytes available in the receive buffer

### `TLSSocket:isconnected()`
Check if the TLS connection is established

**Returns**
1. `boolean` - Whether connected with completed TLS handshake

## Constants

* `TCP` - Socket type constant for TCP
* `UDP` - Socket type constant for UDP
* `_VERSION` - Module version string


# `http` - HTTP client

The HTTP module is a Lua library that provides a simple HTTP/1.1 client built on top of the socket module. It supports both HTTP and HTTPS (via TLS sockets). Assuming you have an SD card with the expected directory structure and Lua files, load with `local http = require("lua/modules/http")`.

## `http.request(url, [options])`
Perform an HTTP request

**Parameters**
1. `url : string` - The full URL to request (http:// or https://)
2. `options : table` - Optional configuration:
   * `method : string` - HTTP method, GET or POST (defaults to GET)
   * `headers : table` - Custom headers as key-value pairs
   * `body : string` - Request body for POST
   * `timeout : number` - Request timeout in seconds, defaults to 30
   * `follow_redirects : boolean` - Follow redirects, defaults to true

**Returns**
1. `table | nil` - Response table, or nil on error:
   * `status : number` - HTTP status code (200, 404, etc.)
   * `reason : string` - Status reason phrase
   * `headers : table` - Response headers (lowercase keys)
   * `body : string` - Response body
2. `string` - Error message if request failed

**Example**
```lua
local http = require("lua/modules/http")

local response, err = http.request("https://api.example.com/data")
if response then
    print("Status:", response.status)
    print("Body:", response.body)
else
    print("Error:", err)
end
```

## `http.get(url, [options])`
Simplified function for GET requests

**Parameters**
1. `url : string` - The URL to fetch
2. `options : table` - Same options as `request()` (method is set to GET)

**Returns**
Same as `request()`

## `http.post(url, body, [content_type], [options])`
Simplified function for POST requests

**Parameters**
1. `url : string` - The URL to post to
2. `body : string` - The request body
3. `content_type : string` - Content-Type header, defaults to "application/x-www-form-urlencoded"
4. `options : table` - Additional options (method is set to POST)

**Returns**
Same as `request()`

**Example**
```lua
local http = require("lua/modules/http")

-- Post form data
local params = http.encode_params({username = "user", password = "pass"})
local response = http.post("https://example.com/login", params)

-- Post JSON
local response = http.post("https://api.example.com/data",
    '{"key": "value"}',
    "application/json")
```

## `http.urlencode(str)`
URL-encode a string

**Parameters**
1. `str : string` - The string to encode

**Returns**
1. `string` - URL-encoded string

## `http.encode_params(params)`
Encode a table of parameters for form submission

**Parameters**
1. `params : table` - Key-value pairs to encode

**Returns**
1. `string` - URL-encoded query string (e.g., "key1=value1&key2=value2")

## Settings

* `http.TIMEOUT` - Set timeout in seconds (default is 30)
* `http.MAX_REDIRECTS` - Maximum redirects to follow (default is 5)
* `http.USER_AGENT` - Set User-Agent header
