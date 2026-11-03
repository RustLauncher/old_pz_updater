require "ProjectALife/Records/ALifeRecordCodec"

ProjectALife = ProjectALife or {}

local Migration = { suffix = ".old", backupSlots = 16, verifiedWrites = {}, verifiedCopies = {}, writeBusy = {}, partialWrites = {}, retiredFiles = {} }
local preparedBodies = {}
ProjectALife.RecordMigration = Migration

function Migration.recordLine(clean)
    if string.match(clean, "^@alife%-records%s+%d") ~= nil then return true end
    local kind, id = string.match(clean, "^(%a+)%s+(%S+)$")
    return kind ~= nil and ProjectALife.RecordCodec.into[kind] ~= nil and ProjectALife.RecordCodec.validId(id)
end

function Migration.isCurrent(text)
    if type(text) ~= "string" then return false end
    local cursor, size, blank = 1, #text, true
    while cursor <= size do
        local ending = string.find(text, "[\r\n]", cursor)
        local clean = string.match(string.sub(text, cursor, ending and ending - 1 or size), "^%s*(.-)%s*$")
        cursor = ending and ending + 1 or size + 1
        if clean ~= "" and string.sub(clean, 1, 2) ~= "--" then
            if Migration.recordLine(clean) then return true end
            blank = false
        end
    end
    return blank
end

function Migration.validFileName(fileName)
    if type(fileName) ~= "string" then return false end
    local stem, suffix = string.match(fileName, "^(alife_[%w_]+)([%.%w]+)$")
    if stem ~= "alife_custom_profiles" and stem ~= "alife_custom_factions"
            and stem ~= "alife_server_profiles" and stem ~= "alife_server_factions"
            and stem ~= "alife_creator_folders" then return false end
    if (stem == "alife_custom_profiles" or stem == "alife_custom_factions")
            and (suffix == ".preseasonal.index.ini" or string.match(suffix, "^%.preseasonal%.[1-9]%.ini$") ~= nil) then
        return true
    end
    return suffix == ".ini" or suffix == ".old.ini"
        or string.match(suffix, "^%.old%.%d%d?%.ini$") ~= nil
        or suffix == ".bad.ini" or string.match(suffix, "^%.bad%.%d%d?%.ini$") ~= nil
        or suffix == ".ini.backup.ini" or suffix == ".ini.damaged.ini"
end

function Migration.badName(fileName, slot)
    local stem = type(fileName) == "string" and string.match(fileName, "^(alife_[%w_]+)%.ini$") or nil
    if stem == nil or not Migration.validFileName(fileName) then return nil end
    local index = tonumber(slot)
    if index ~= nil and index > 0 then return stem .. ".bad." .. tostring(math.floor(index)) .. ".ini" end
    return stem .. ".bad.ini"
end

function Migration.backupName(fileName, slot)
    if not Migration.validFileName(fileName) then return nil end
    local stem, extension = string.match(fileName, "^(.*)(%.[%w]+)$")
    if stem == nil then return fileName .. Migration.suffix .. ".txt" end
    local index = tonumber(slot)
    if index ~= nil and index > 0 then
        return stem .. Migration.suffix .. "." .. tostring(math.floor(index)) .. extension
    end
    return stem .. Migration.suffix .. extension
end

function Migration.writeFile(fileName, text)
    if not Migration.validFileName(fileName) or type(text) ~= "string" then return false end
    if type(getFileWriter) ~= "function" then return false end
    local writer
    local ok, written = pcall(function()
        writer = getFileWriter(fileName, true, false)
        if writer == nil then return false end
        writer:write(text)
        return true
    end)
    local closed = writer ~= nil and pcall(function() writer:close() end)
    return ok and written == true and closed == true
end

Migration.byteOrderMark = "\239\187\191"

function Migration.withoutMark(text)
    local mark = Migration.byteOrderMark
    if type(text) ~= "string" or string.sub(text, 1, #mark) ~= mark then return text end
    return string.sub(text, #mark + 1)
end

function Migration.unwrapSaved(text)
    local stop = string.find(text, "\n", 1, true)
    if stop == nil then return nil end
    local size = string.match(string.sub(text, 1, stop - 1), "^@alife%-save (%d+)$")
    if size == nil then return nil end
    local last = #text - 15
    if last <= stop or string.sub(text, last) ~= "\n@alife-save-end" then return nil end
    local body = string.sub(text, stop + 1, last - 1)
    if #body ~= tonumber(size) then return nil end
    return body
end

function Migration.savedBodyStart(text, kind, source)
    if type(text) ~= "string" then return true end
    if string.sub(text, 1, 12) == "@alife-save " then
        text = Migration.unwrapSaved(text)
        if text == nil then return true end
    end
    if type(kind) == "function" then
        local body, why = kind(text)
        return true, body, why
    end
    if not Migration.isCurrent(text) then return true, nil, "retired" end
    return false, text, nil, ProjectALife.RecordCodec.decodeStart(text, { kind = kind, text = true, source = source })
end

function Migration.savedBodyFinish(text, parsed)
    if parsed == nil or (#parsed.records == 0 and string.find(text, "%S") ~= nil) then return nil end
    return text
end

function Migration.savedBody(text, kind, keep)
    local source = type(keep) == "table" and keep.source or nil
    local done, body, why, decoder = Migration.savedBodyStart(text, kind, source)
    if done then return body, why end
    local _, parsed = ProjectALife.RecordCodec.decodeStep(decoder, nil)
    body = Migration.savedBodyFinish(body, parsed)
    if body ~= nil and type(keep) == "table" then keep.parsed = parsed end
    return body
end

function Migration.readBegin(fileName)
    local state = { fileName = fileName, lines = {}, count = 0 }
    if not Migration.validFileName(fileName) or type(getFileReader) ~= "function" then
        state.finished, state.readable = true, false
        return state
    end
    local ok, reader = pcall(getFileReader, fileName, false)
    if not ok then
        state.finished, state.readable = true, false
        return state
    end
    if reader == nil then
        state.finished, state.readable = true, true
        return state
    end
    state.reader = reader
    return state
end

function Migration.readLines(state, budgetMs)
    local reader, lines, count = state.reader, state.lines, state.count
    local startedAt = budgetMs ~= nil and Migration.transactionClock() or nil
    while true do
        local line = reader:readLine()
        if line == nil then
            state.count = count
            return true
        end
        count = count + 1
        lines[count] = line
        if startedAt ~= nil and count % 128 == 0 then
            local now = Migration.transactionClock()
            if now == nil or now < startedAt or now - startedAt >= budgetMs then
                state.count = count
                return false
            end
        end
    end
end

function Migration.readStep(state, budgetMs)
    if state.finished then return true end
    local ran, ended = pcall(Migration.readLines, state, budgetMs)
    if ran and not ended then return false end
    local reader = state.reader
    state.reader, state.finished = nil, true
    local closed = true
    if reader ~= nil then closed = pcall(function() reader:close() end) end
    if not ran then
        state.lines, state.readable = nil, false
        return true
    end
    local text = Migration.withoutMark(table.concat(state.lines, "\n"))
    state.lines, state.text, state.readable = nil, text, closed
    return true
end

function Migration.readFile(fileName)
    local state = Migration.readBegin(fileName)
    Migration.readStep(state, nil)
    return state.text, state.readable
end

function Migration.countRecords(text, kind)
    if type(kind) ~= "string" or type(text) ~= "string" then return 0 end
    local mark, count, at = "\n" .. kind .. " ", 0, 1
    if string.sub(text, 1, #mark - 1) == string.sub(mark, 2) then count = 1 end
    while true do
        at = string.find(text, mark, at, true)
        if at == nil then return count end
        count = count + 1
        at = at + #mark
    end
end

function Migration.readSavedBegin(fileName, kind, keep)
    local state = { fileName = fileName, kind = kind, keep = type(keep) == "table" and keep or nil, phase = "read" }
    if state.keep ~= nil then state.keep.parsed, state.keep.reused = nil, nil end
    if not Migration.validFileName(fileName) then
        state.phase, state.origin, state.body = "done", "invalid_file_name", nil
        return state
    end
    Migration.retiredFiles[fileName] = nil
    state.reader = Migration.readBegin(fileName)
    return state
end

function Migration.readSavedStep(state, budgetMs)
    if state.phase == "read" then
        if not Migration.readStep(state.reader, budgetMs) then return false end
        state.raw, state.readable = state.reader.text, state.reader.readable
        state.reader, state.phase = nil, "body"
        if budgetMs ~= nil then return false end
    end
    local keep = state.keep
    if state.phase == "body" then
        state.phase = "tail"
        if state.readable then
            local known = keep ~= nil and keep.knownRaw ~= nil and keep.knownRaw == state.raw
            if known then
                local text = state.raw
                if string.sub(text, 1, 12) == "@alife-save " then text = Migration.unwrapSaved(text) end
                if text ~= nil then
                    state.body, keep.parsed, keep.reused = text, keep.knownParsed, true
                    state.total = #keep.knownParsed.records
                end
            end
            if state.body == nil then
                local done, body, why, decoder = Migration.savedBodyStart(state.raw, state.kind, keep and keep.source)
                if done then state.body, state.why = body, why
                else
                    state.text, state.decoder, state.phase = body, decoder, "decode"
                    state.total = Migration.countRecords(body, state.kind)
                end
            end
        end
        if budgetMs ~= nil and state.phase == "decode" then return false end
    end
    if state.phase == "decode" then
        local done, parsed = ProjectALife.RecordCodec.decodeStep(state.decoder, budgetMs)
        if not done then return false end
        state.body = Migration.savedBodyFinish(state.text, parsed)
        state.decoded = parsed ~= nil and #parsed.records or nil
        if state.body ~= nil and keep ~= nil then keep.parsed = parsed end
        state.decoder, state.text, state.phase = nil, nil, "tail"
        if budgetMs ~= nil then return false end
    end
    if state.phase == "tail" then
        if state.body == nil or (string.find(state.body, "%S") == nil and string.sub(state.raw or "", 1, 12) ~= "@alife-save ") then
            if not Migration.readBackupStep(state, budgetMs) then return false end
        end
        state.body, state.origin, state.raw = Migration.readSavedTail(state)
        state.phase = "done"
    end
    return true, state.body, state.origin, state.raw
end

function Migration.readBackupStep(state, budgetMs)
    local keep = state.keep
    if state.backup == nil then
        if keep ~= nil then keep.parsed, keep.reused = nil, nil end
        state.backup = { phase = "read", reader = Migration.readBegin(state.fileName .. ".backup.ini") }
    end
    local backup = state.backup
    if backup.phase == "read" then
        if not Migration.readStep(backup.reader, budgetMs) then return false end
        backup.raw, backup.readable = backup.reader.text, backup.reader.readable
        backup.reader, backup.phase = nil, "body"
        if budgetMs ~= nil then return false end
    end
    if backup.phase == "body" then
        backup.phase = "done"
        if backup.readable then
            local done, body, why, decoder = Migration.savedBodyStart(backup.raw, state.kind, keep and keep.source)
            if done then backup.body = body
            else
                backup.text, backup.decoder, backup.phase = body, decoder, "decode"
                state.total = Migration.countRecords(body, state.kind)
            end
        end
        if budgetMs ~= nil and backup.phase == "decode" then return false end
    end
    if backup.phase == "decode" then
        local done, parsed = ProjectALife.RecordCodec.decodeStep(backup.decoder, budgetMs)
        if not done then return false end
        backup.body = Migration.savedBodyFinish(backup.text, parsed)
        if backup.body ~= nil and keep ~= nil then keep.parsed = parsed end
        backup.decoder, backup.text, backup.phase = nil, nil, "done"
    end
    return true
end

function Migration.readSavedTail(state)
    local fileName, kind, raw, body, keep = state.fileName, state.kind, state.raw, state.body, state.keep
    if body ~= nil and (string.find(body, "%S") ~= nil or string.sub(raw, 1, 12) == "@alife-save ") then
        if type(kind) == "string" then Migration.verifiedWrites[fileName] = { text = raw, kind = kind } end
        return body, "primary", raw
    end
    local backup, backupReadable = state.backup.raw, state.backup.readable
    local recovered = state.backup.body
    if recovered ~= nil then
        if type(kind) == "string" then
            Migration.verifiedCopies[fileName .. ".backup.ini"] = { text = backup, kind = kind }
            Migration.partialWrites[fileName] = true
        end
        return recovered, "backup", backup
    end
    if state.why == "retired" then
        if kind == "member" or kind == "faction" then Migration.retiredFiles[fileName] = { text = raw, kind = kind } end
        return nil, "retired", raw
    end
    if state.readable and (raw == nil or body ~= nil) and backup == nil and backupReadable then
        Migration.verifiedWrites[fileName], Migration.verifiedCopies[fileName .. ".backup.ini"], Migration.partialWrites[fileName] = nil, nil, nil
        return "", "empty", raw
    end
    return nil, "unreadable"
end

function Migration.readSaved(fileName, kind, keep)
    local state = Migration.readSavedBegin(fileName, kind, keep)
    if state.phase == "done" then return nil, state.origin end
    local _, body, origin, raw = Migration.readSavedStep(state, nil)
    return body, origin, raw
end

function Migration.beginPrepared(kind)
    if kind ~= "member" and kind ~= "faction" then return nil end
    local handle = {}
    preparedBodies[handle] = { kind = kind, parts = {}, seen = {} }
    return handle
end

function Migration.addPrepared(handle, text, trustedId)
    local state = preparedBodies[handle]
    if state == nil or state.ready then return false end
    local valid
    if trustedId ~= nil and type(text) == "string" then
        valid = ProjectALife.RecordCodec.validId(trustedId) and not state.seen[trustedId]
        if valid then state.seen[trustedId] = true end
    else valid = ProjectALife.RecordCodec.validatePart(text, state.kind, state.seen) end
    if not valid then preparedBodies[handle] = nil; return false end
    state.parts[#state.parts + 1] = text
    return true
end

function Migration.finishPrepared(handle)
    local state = preparedBodies[handle]
    if state == nil then return nil end
    if not state.ready then
        state.text = table.concat(state.parts, "\n\n")
        state.parts, state.seen, state.ready = nil, nil, true
    end
    return state.text
end

function Migration.cancelPrepared(handle)
    local state = preparedBodies[handle]
    if state ~= nil and state.transaction ~= nil then
        local transaction = state.transaction
        Migration.closeTransactionIO(transaction)
        if Migration.writeBusy[transaction.fileName] == transaction then Migration.writeBusy[transaction.fileName] = nil end
    end
    preparedBodies[handle] = nil
end

function Migration.closeStream(stream)
    if stream == nil or type(stream.close) ~= "function" then return false end
    return pcall(stream.close, stream)
end

function Migration.closeTransactionIO(transaction)
    local io = transaction.io
    if io == nil then return true end
    transaction.io = nil
    if io.stream == nil then return true end
    if type(io.stream.close) ~= "function" then return false end
    return pcall(io.stream.close, io.stream)
end

function Migration.beginPreparedWrite(handle, fileName, text, kind)
    local state = preparedBodies[handle]
    if state == nil or not state.ready or state.kind ~= kind or state.text ~= text
            or state.transaction ~= nil or not Migration.validFileName(fileName)
            or Migration.writeBusy[fileName] ~= nil then return false end
    local transaction = { fileName = fileName, kind = kind, phase = "old",
        sealed = "@alife-save " .. tostring(#text) .. "\n" .. text .. "\n@alife-save-end" }
    state.transaction = transaction
    Migration.writeBusy[fileName] = transaction
    return true
end

function Migration.openTransactionIO(transaction, mode, fileName, text)
    if transaction.io ~= nil then return false end
    local stream, bulk, lined
    if mode == "read" then
        if Migration.lineReads ~= false and type(getFileReader) == "function" then
            stream = getFileReader(fileName, false)
            if stream == nil then lined = true
            elseif type(stream.close) == "function" and type(stream.readLine) == "function" then lined = true
            else
                Migration.closeStream(stream)
                stream = nil
            end
        end
        if not lined and type(getFileInput) == "function" then
            stream = getFileInput(fileName)
            if stream ~= nil then
                transaction.io = { stream = stream }
                if type(stream.close) ~= "function" then return false end
                if type(stream.readNBytes) == "function" then bulk = true
                else
                    if not Migration.closeTransactionIO(transaction) then return false end
                    stream = nil
                end
            end
        end
        if not bulk and not lined then
            if type(getFileReader) ~= "function" then return false end
            stream = getFileReader(fileName, false)
        end
    else
        if type(getFileWriter) ~= "function" then return false end
        stream = getFileWriter(fileName, true, false)
        if stream ~= nil and fileName == transaction.fileName then Migration.partialWrites[fileName] = true end
    end
    transaction.io = { stream = stream, mode = mode, text = text, cursor = 1, parts = {}, bulk = bulk, lined = lined }
    if lined then transaction.lined = true end
    if bulk then transaction.io.wide = pcall(string.char, 256) end
    if stream ~= nil and type(stream.close) ~= "function" then return false end
    if mode == "read" then return stream == nil or bulk or lined or type(stream.read) == "function" end
    if stream == nil or type(stream.write) ~= "function" then return false end
    if string.sub(text, -1) == "\n" then transaction.io.writeText = text .. "\n" end
    return true
end

function Migration.compareTransactionChunk(io, chunk)
    if io.text ~= nil then
        if string.sub(io.text, io.cursor, io.cursor + #chunk - 1) ~= chunk then return false end
        io.cursor = io.cursor + #chunk
    else io.parts[#io.parts + 1] = chunk end
    return true
end

function Migration.transactionClock()
    if type(getTimestampMs) == "function" then return tonumber(getTimestampMs()) end
    return nil
end

function Migration.validTransactionBytes(bytes)
    if type(bytes) ~= "table" then return false end
    local size, count = #bytes, 0
    if size > 2048 then return false end
    for key, value in pairs(bytes) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > size then return false end
        if type(value) ~= "number" or value % 1 ~= 0 or value < -128 or value > 255 then return false end
        count = count + 1
    end
    return count == size
end

function Migration.decodeTransactionBytes(io, bytes, ended)
    if type(bytes) ~= "table" then return nil end
    local size, count = #bytes, 0
    if size > 8192 then return nil end
    for key, value in pairs(bytes) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > size then return nil end
        if type(value) ~= "number" or value % 1 ~= 0 or value < -128 or value > 255 then return nil end
        bytes[key] = value < 0 and value + 256 or value
        count = count + 1
    end
    if count ~= size then return nil end
    if Migration.byteCharacters == nil then
        Migration.byteCharacters = {}
        for code = 0, 127 do Migration.byteCharacters[code] = string.char(code) end
    end
    local input, chars = io.carry or bytes, {}
    local inputSize, charCount = io.carry and #io.carry or 0, 0
    for index = 1, size do
        inputSize = inputSize + 1
        input[inputSize] = bytes[index]
    end
    io.carry = nil
    local cursor = 1
    while cursor <= inputSize do
        local first, width, code = input[cursor], 1, input[cursor]
        if first < 128 and first ~= 10 and first ~= 13 and type(unpack) == "function" then
            local ending = cursor
            while ending < inputSize and ending - cursor < 127 do
                local nextCode = input[ending + 1]
                if nextCode >= 128 or nextCode == 10 or nextCode == 13 then break end
                ending = ending + 1
            end
            local span = string.char(unpack(input, cursor, ending))
            if io.pending ~= nil then charCount = charCount + 1; chars[charCount] = io.pending end
            if #span > 1 then charCount = charCount + 1; chars[charCount] = string.sub(span, 1, -2) end
            io.pending, io.afterCR, cursor = string.sub(span, -1), false, ending + 1
        else
        if first >= 194 and first <= 223 then width, code = 2, first - 192
        elseif first >= 224 and first <= 239 then width, code = 3, first - 224
        elseif first >= 240 and first <= 244 then width, code = 4, first - 240
        elseif first > 127 then return nil end
        if cursor + width - 1 > inputSize then
            if ended then return nil end
            io.carry = {}
            for index = cursor, inputSize do io.carry[index - cursor + 1] = input[index] end
            break
        end
        for index = cursor + 1, cursor + width - 1 do
            local value = input[index]
            if value < 128 or value > 191 then return nil end
            code = code * 64 + value - 128
        end
        if (width == 2 and code < 128) or (width == 3 and code < 2048)
                or (width == 4 and code < 65536) or code > 1114111
                or (code >= 55296 and code <= 57343) then return nil end
        local encoded
        if width == 1 then encoded = Migration.byteCharacters[first]
        elseif io.wide then
            if code <= 65535 then encoded = string.char(code)
            else
                local scalar = code - 65536
                encoded = string.char(55296 + math.floor(scalar / 1024), 56320 + scalar % 1024)
            end
        elseif width == 2 then encoded = string.char(first, input[cursor + 1])
        elseif width == 3 then encoded = string.char(first, input[cursor + 1], input[cursor + 2])
        else encoded = string.char(first, input[cursor + 1], input[cursor + 2], input[cursor + 3]) end
        if code ~= 10 or not io.afterCR then
            if io.pending ~= nil then charCount = charCount + 1; chars[charCount] = io.pending end
            io.pending = code == 13 and "\n" or encoded
        end
        io.afterCR = code == 13
        cursor = cursor + width
        end
    end
    return chars
end

Migration.lineBatch = 4000
Migration.stepMs = 5

function Migration.stepLinedRead(transaction, io)
    local lines, count, ended, stream = {}, 0, false, io.stream
    local startedAt = Migration.transactionClock()
    while count < Migration.lineBatch do
        local line = stream:readLine()
        if line == nil then ended = true; break end
        if type(line) ~= "string" then return false, false end
        count = count + 1
        lines[count] = line
        if count % 128 == 0 and startedAt ~= nil then
            local now = Migration.transactionClock()
            if now ~= nil and now - startedAt >= Migration.stepMs then break end
        end
    end
    if count > 0 then
        local chunk = table.concat(lines, "\n")
        if io.joined then chunk = "\n" .. chunk end
        io.joined = true
        if not Migration.compareTransactionChunk(io, chunk) then return false, false end
    end
    if not ended then return true, false end
    if io.text ~= nil and io.cursor ~= #io.text + 1 then return false, false end
    if io.text == nil then transaction.readText = Migration.withoutMark(table.concat(io.parts)) end
    return Migration.closeTransactionIO(transaction), true
end

function Migration.stepTransactionIO(transaction)
    local io = transaction.io
    if io == nil then return false, false end
    if io.mode == "write" then
        local text = io.writeText or io.text
        local ending = math.min(#text, io.cursor + 16383)
        if io.cursor <= ending then io.stream:write(string.sub(text, io.cursor, ending)); io.cursor = ending + 1 end
        if io.cursor <= #text then return true, false end
        return Migration.closeTransactionIO(transaction), true
    end
    if io.stream == nil then
        transaction.readText = nil
        transaction.io = nil
        return io.text == nil, true
    end
    if io.lined then return Migration.stepLinedRead(transaction, io) end
    local chars, ended, startedAt = {}, false, Migration.transactionClock()
    if io.bulk then
        if io.bytes == nil then
            if transaction.readBudget ~= nil and transaction.readBudget < 2048 then return true, false end
            local bytes = io.stream:readNBytes(2048)
            if not Migration.validTransactionBytes(bytes) then return false, false end
            if transaction.readBudget ~= nil then transaction.readBudget = transaction.readBudget - 2048 end
            io.bytes, io.byteCursor = bytes, 1
        end
        local size, part = #io.bytes, {}
        local ending = math.min(size, io.byteCursor + 511)
        for index = io.byteCursor, ending do part[#part + 1] = io.bytes[index] end
        ended = size == 0
        chars = Migration.decodeTransactionBytes(io, part, ended)
        if chars == nil then return false, false end
        io.byteCursor = ending + 1
        if io.byteCursor > size then io.bytes, io.byteCursor = nil, nil end
    else for index = 1, 8192 do
        local code = io.stream:read()
        if code == -1 then ended = true; break end
        if type(code) ~= "number" or code < 0 or code > 65535 then return false, false end
        if code ~= 10 or not io.afterCR then
            if io.pending ~= nil then chars[#chars + 1] = io.pending end
            io.pending = code == 13 and "\n" or string.char(code)
        end
        io.afterCR = code == 13
        if index % 128 == 0 and startedAt ~= nil then
            local now = Migration.transactionClock()
            if now ~= nil and now - startedAt >= 4 then break end
        end
    end end
    if ended and io.pending ~= nil and io.pending ~= "\n" then chars[#chars + 1] = io.pending end
    if not Migration.compareTransactionChunk(io, table.concat(chars)) then return false, false end
    if not ended then return true, false end
    if io.text ~= nil and io.cursor ~= #io.text + 1 then return false, false end
    if io.text == nil then transaction.readText = Migration.withoutMark(table.concat(io.parts)) end
    return Migration.closeTransactionIO(transaction), true
end

function Migration.stepPreparedWriteBody(transaction)
    local phase, name = transaction.phase, transaction.fileName
    local backupName = name .. ".backup.ini"
    if phase == "done" then return true, true end
    if transaction.io == nil then
        if phase == "old" then return Migration.openTransactionIO(transaction, "read", name), false end
        if phase == "reuse" or phase == "recover" then
            return Migration.openTransactionIO(transaction, "read", backupName, transaction.backup), false
        end
        if phase == "retired" then
            return Migration.openTransactionIO(transaction, "read", transaction.retiredBackup, transaction.old), false
        end
        if phase == "copy" then return Migration.openTransactionIO(transaction, "write", transaction.copyName, transaction.copyText), false end
        if phase == "copyCheck" then return Migration.openTransactionIO(transaction, "read", transaction.copyName, transaction.copyText), false end
        if phase == "primary" then return Migration.openTransactionIO(transaction, "write", name, transaction.sealed), false end
        if phase == "primaryCheck" then return Migration.openTransactionIO(transaction, "read", name, transaction.sealed), false end
        return false, false
    end
    local ok, ready = Migration.stepTransactionIO(transaction)
    if not ok then
        if phase == "reuse" then
            Migration.closeTransactionIO(transaction)
            transaction.copyName, transaction.copyText, transaction.phase = backupName, transaction.old, "copy"
            return true, false
        elseif phase == "recover" and transaction.emptyRecover then
            Migration.closeTransactionIO(transaction)
            transaction.copyName, transaction.copyText, transaction.phase = name .. ".damaged.ini", transaction.old, "copy"
            transaction.afterCopy = "seed"
            return true, false
        end
        return false, false
    end
    if not ready then return true, false end
    if phase == "old" then
        transaction.old = transaction.readText
        local known, backup = Migration.verifiedWrites[name], Migration.verifiedCopies[backupName]
        if transaction.old == nil and not Migration.partialWrites[name] then
            transaction.copyName, transaction.copyText, transaction.phase = backupName, transaction.sealed, "copy"
        elseif known ~= nil and known.kind == transaction.kind and known.text == transaction.old then
            transaction.same = transaction.old == transaction.sealed
            transaction.copyName, transaction.copyText = backupName, transaction.old
            if backup ~= nil and backup.kind == transaction.kind and (transaction.same or backup.text == transaction.old) then
                transaction.backup, transaction.phase = backup.text, "reuse"
            else transaction.phase = "copy" end
        elseif Migration.retiredFiles[name] ~= nil and Migration.retiredFiles[name].kind == transaction.kind
                and Migration.retiredFiles[name].text == transaction.old
                and type(Migration.retiredFiles[name].backup) == "string" then
            transaction.retiredBackup, transaction.phase = Migration.retiredFiles[name].backup, "retired"
        elseif Migration.partialWrites[name] and backup ~= nil and backup.kind == transaction.kind then
            transaction.backup, transaction.phase = backup.text, "recover"
        elseif transaction.old ~= nil and string.find(transaction.old, "%S") == nil then
            if backup ~= nil and backup.kind == transaction.kind then
                transaction.backup, transaction.phase, transaction.emptyRecover = backup.text, "recover", true
            else
                transaction.copyName, transaction.copyText, transaction.phase = name .. ".damaged.ini", transaction.old, "copy"
                transaction.afterCopy = "seed"
            end
        else return false, false end
    elseif phase == "retired" then
        transaction.copyName, transaction.copyText, transaction.phase = backupName, transaction.sealed, "copy"
    elseif phase == "recover" then
        if transaction.old == nil then transaction.phase = "primary"
        else transaction.copyName, transaction.copyText, transaction.phase = name .. ".damaged.ini", transaction.old, "copy" end
    elseif phase == "reuse" then transaction.phase = transaction.same and "done" or "primary"
    elseif phase == "copy" then transaction.phase = "copyCheck"
    elseif phase == "copyCheck" then
        Migration.verifiedCopies[transaction.copyName] = { text = transaction.copyText, kind = transaction.kind }
        if transaction.afterCopy == "seed" then
            transaction.copyName, transaction.copyText, transaction.phase = backupName, transaction.sealed, "copy"
            transaction.afterCopy = nil
        else transaction.phase = transaction.same and "done" or "primary" end
    elseif phase == "primary" then transaction.phase = "primaryCheck"
    elseif phase == "primaryCheck" then
        Migration.verifiedWrites[name] = { text = transaction.sealed, kind = transaction.kind }
        Migration.partialWrites[name] = nil
        Migration.retiredFiles[name] = nil
        transaction.phase = "done"
    end
    return true, transaction.phase == "done"
end

function Migration.stepPreparedWrite(handle)
    local state = preparedBodies[handle]
    local transaction = state and state.transaction
    if transaction == nil or Migration.writeBusy[transaction.fileName] ~= transaction then return false, false end
    local startedAt = Migration.transactionClock()
    transaction.readBudget = 8192
    for index = 1, 256 do
        local io = transaction.io
        local ran, ok, ready = pcall(Migration.stepPreparedWriteBody, transaction)
        if not ran or not ok then
            Migration.closeTransactionIO(transaction)
            return false, false
        end
        if ready then return true, true end
        if startedAt == nil then return true, false end
        if transaction.lined then
            local now = Migration.transactionClock()
            if now == nil or now < startedAt or now - startedAt >= Migration.stepMs then return true, false end
        else
            if io == nil or not io.bulk or io.mode ~= "read" then return true, false end
            if transaction.readBudget == 0 and (transaction.io == nil or transaction.io.bytes == nil) then return true, false end
            local now = Migration.transactionClock()
            if now == nil or now < startedAt or now - startedAt >= 24 then return true, false end
        end
    end
    return true, false
end

function Migration.verifiedCopy(fileName, text, kind)
    local known = Migration.verifiedCopies[fileName]
    if known ~= nil and known.kind == kind and known.text == text then
        local existing, readable = Migration.readFile(fileName)
        if readable and existing == text then return true end
    end
    if not Migration.writeFile(fileName, text) then return false end
    local copy, copied = Migration.readFile(fileName)
    if not copied or copy ~= text then return false end
    Migration.verifiedCopies[fileName] = { text = text, kind = kind }
    return true
end

function Migration.persistSaved(fileName, text, kind, prepared)
    if not Migration.validFileName(fileName) or Migration.writeBusy[fileName] ~= nil then return false end
    local preparation = preparedBodies[prepared]
    if preparation == nil or not preparation.ready or preparation.kind ~= kind or preparation.text ~= text then
        if Migration.savedBody(text, kind) == nil then return false end
    else
        preparedBodies[prepared] = nil
    end
    local sealed = "@alife-save " .. tostring(#text) .. "\n" .. text .. "\n@alife-save-end"
    local raw, readable = Migration.readFile(fileName)
    if not readable then return false end
    local known = Migration.verifiedWrites[fileName]
    if raw == sealed and type(kind) == "string" and known ~= nil and known.kind == kind and known.text == raw then
        local backupName = fileName .. ".backup.ini"
        local backup = Migration.verifiedCopies[backupName]
        if backup ~= nil and backup.kind == kind then
            local existing, copied = Migration.readFile(backupName)
            if copied and existing == backup.text then return true end
        end
        return Migration.verifiedCopy(backupName, raw, kind)
    end
    if raw ~= nil then
        local valid = type(kind) == "string" and known ~= nil and known.kind == kind and known.text == raw
        if not valid then
            local old = Migration.savedBody(raw, kind)
            valid = old ~= nil and (string.find(old, "%S") ~= nil or string.sub(raw, 1, 12) == "@alife-save ")
        end
        local copyName = fileName .. (valid and ".backup.ini" or ".damaged.ini")
        if not Migration.verifiedCopy(copyName, raw, kind) then return false end
    end
    if raw == nil then
        if not Migration.verifiedCopy(fileName .. ".backup.ini", sealed, kind) then return false end
    end
    if not Migration.writeFile(fileName, sealed) then return false end
    local saved, checked = Migration.readFile(fileName)
    local verified = checked and saved == sealed
    if verified and type(kind) == "string" then Migration.verifiedWrites[fileName] = { text = sealed, kind = kind } end
    return verified
end

function Migration.keepOld(fileName, text, namer)
    namer = namer or Migration.backupName
    if namer(fileName) == nil or type(text) ~= "string" then
        return false, "migration_backup_invalid"
    end
    local expected = string.gsub(string.gsub(text, "\r\n", "\n"), "\r", "\n")
    expected = string.gsub(expected, "\n$", "")
    local unreadable = false
    for slot = 0, Migration.backupSlots do
        local backup = namer(fileName, slot)
        local existing, readable = Migration.readFile(backup)
        if not readable then
            unreadable = true
        elseif existing == expected then
            return true, nil, backup
        elseif existing == nil or existing == "" then
            if not Migration.writeFile(backup, text) then return false, "migration_backup_write_failed" end
            local copy, copied = Migration.readFile(backup)
            if not copied or copy ~= expected then return false, "migration_backup_verify_failed" end
            return true, nil, backup, true
        end
    end
    if unreadable then return false, "migration_backup_unreadable" end
    return false, "migration_backup_slots_full"
end

function Migration.setAside(fileName, text, label)
    label = type(label) == "string" and label or ("The Creator file " .. tostring(fileName))
    local kept, reason, backup, fresh = Migration.keepOld(fileName, text)
    if not kept then
        print("[A-Life] " .. label .. " is not record text and was not loaded; no backup could be written ("
            .. tostring(reason) .. ")")
        return false, reason
    end
    local retired = Migration.retiredFiles[fileName]
    if retired ~= nil and retired.text == text then retired.backup = backup end
    if fresh == true then
        local notice = "Project A-Life: " .. label .. " is not in the current record format"
            .. " (saved before 1.2) and was not loaded.\nThe original is kept in Zomboid/Lua/"
            .. tostring(backup) .. "."
        print("[A-Life] " .. notice)
        ProjectALife.RecordSalvage.notify(notice)
    end
    return true, nil, backup
end

Migration.snapshotSlots = 3
Migration.snapshotIndexName = "alife_custom_profiles.preseasonal.index.ini"

function Migration.snapshotName(fileName, slot)
    local stem = type(fileName) == "string" and string.match(fileName, "^(alife_custom_%a+)%.ini$") or nil
    if stem ~= "alife_custom_profiles" and stem ~= "alife_custom_factions" then return nil end
    local index = tonumber(slot)
    if index == nil or index % 1 ~= 0 or index < 1 or index > Migration.snapshotSlots then return nil end
    return stem .. ".preseasonal." .. tostring(index) .. ".ini"
end

function Migration.snapshotStamp()
    local ok, text = pcall(function() return os.date("%Y%m%d_%H%M%S") end)
    if ok and type(text) == "string" and string.match(text, "^%d%d%d%d%d%d%d%d_%d%d%d%d%d%d$") ~= nil then return text end
    return "unknown"
end

function Migration.snapshotEntries()
    local text, readable = Migration.readFile(Migration.snapshotIndexName)
    if not readable then return nil end
    local entries = {}
    for line in string.gmatch(tostring(text or "") .. "\n", "(.-)\n") do
        local slot, stamp, profiles, factions = string.match(line, "^slot=(%d) stamp=(%S+) profiles=([01]) factions=([01])%s*$")
        slot = tonumber(slot)
        if slot ~= nil and slot >= 1 and slot <= Migration.snapshotSlots then
            for index = #entries, 1, -1 do
                if entries[index].slot == slot then table.remove(entries, index) end
            end
            entries[#entries + 1] = { slot = slot, stamp = stamp, profiles = profiles == "1", factions = factions == "1" }
        end
    end
    return entries
end

function Migration.snapshotPick(entries)
    local used = {}
    for _, entry in ipairs(entries) do used[entry.slot] = true end
    for slot = 1, Migration.snapshotSlots do
        if not used[slot] then return slot end
    end
    return entries[1].slot
end

function Migration.snapshotBegin(sources)
    local entries = Migration.snapshotEntries()
    if entries == nil then return nil, "snapshot_index_unreadable" end
    local slot = Migration.snapshotPick(entries)
    local jobs = {}
    for _, source in ipairs(sources or {}) do
        local target = Migration.snapshotName(source, slot)
        if target == nil or not Migration.validFileName(source) or not Migration.validFileName(target) then
            return nil, "snapshot_name_invalid"
        end
        jobs[#jobs + 1] = { source = source, target = target, phase = "read" }
    end
    if #jobs == 0 then return nil, "snapshot_name_invalid" end
    return { jobs = jobs, cursor = 1, slot = slot, entries = entries, stamp = Migration.snapshotStamp(), names = {}, kept = {}, bytes = 0 }
end

function Migration.snapshotJob(state, job)
    if job.phase == "read" then
        if job.reader == nil then job.reader = Migration.readBegin(job.source) end
        if not Migration.readStep(job.reader, Migration.stepMs) then return true, false end
        local reader = job.reader
        job.reader = nil
        if reader.readable ~= true then return false, false, "snapshot_source_unreadable" end
        job.text = reader.text
        job.phase = job.text == nil and "absent" or "write"
        return true, false
    end
    if job.phase == "absent" then
        local stale, readable = Migration.readFile(job.target)
        if not readable then return false, false, "snapshot_write_failed" end
        if stale ~= nil and stale ~= "" and not Migration.writeFile(job.target, "") then return false, false, "snapshot_write_failed" end
        return true, true
    end
    if job.phase == "write" then
        state.touched = true
        if job.transaction == nil then
            job.transaction = { fileName = job.source }
            if not Migration.openTransactionIO(job.transaction, "write", job.target, job.text) then return false, false, "snapshot_write_failed" end
        end
        local ok, ready = Migration.stepTransactionIO(job.transaction)
        if not ok then return false, false, "snapshot_write_failed" end
        if ready then job.transaction, job.phase = nil, "check" end
        return true, false
    end
    if job.transaction == nil then
        job.transaction = { fileName = job.source }
        if not Migration.openTransactionIO(job.transaction, "read", job.target, job.text) then return false, false, "snapshot_verify_failed" end
    end
    local ok, ready = Migration.stepTransactionIO(job.transaction)
    if not ok then return false, false, "snapshot_verify_failed" end
    if not ready then return true, false end
    job.transaction = nil
    state.names[#state.names + 1] = job.target
    state.kept[job.source] = true
    state.bytes = state.bytes + #job.text
    job.text = nil
    return true, true
end

function Migration.snapshotIndexText(entries)
    local lines = {}
    for _, entry in ipairs(entries) do
        lines[#lines + 1] = "slot=" .. tostring(entry.slot) .. " stamp=" .. tostring(entry.stamp)
            .. " profiles=" .. (entry.profiles and "1" or "0") .. " factions=" .. (entry.factions and "1" or "0")
    end
    return table.concat(lines, "\n")
end

function Migration.snapshotWriteIndex(entries)
    local text = Migration.snapshotIndexText(entries)
    if not Migration.writeFile(Migration.snapshotIndexName, text) then return false end
    local back, readable = Migration.readFile(Migration.snapshotIndexName)
    return readable and back == text
end

function Migration.snapshotFinish(state)
    if #state.names > 0 then
        local entries = {}
        for _, entry in ipairs(state.entries) do
            if entry.slot ~= state.slot then entries[#entries + 1] = entry end
        end
        entries[#entries + 1] = { slot = state.slot, stamp = state.stamp,
            profiles = state.kept["alife_custom_profiles.ini"] == true, factions = state.kept["alife_custom_factions.ini"] == true }
        if not Migration.snapshotWriteIndex(entries) then return false, false, "snapshot_index_failed" end
    end
    state.finished = true
    return true, true
end

function Migration.snapshotAbort(state)
    for _, job in ipairs(state.jobs) do
        if job.transaction ~= nil then
            Migration.closeTransactionIO(job.transaction)
            job.transaction = nil
        end
        job.text, job.reader = nil, nil
    end
    if state.touched then
        local entries = {}
        for _, entry in ipairs(state.entries) do
            if entry.slot ~= state.slot then entries[#entries + 1] = entry end
        end
        pcall(Migration.snapshotWriteIndex, entries)
    end
    state.finished = true
end

function Migration.snapshotStep(state, budgetMs)
    if state.finished then return true, true end
    local startedAt = budgetMs ~= nil and Migration.transactionClock() or nil
    while true do
        local job = state.jobs[state.cursor]
        local ok, done, reason
        if job == nil then
            ok, done, reason = Migration.snapshotFinish(state)
            if ok then return true, true end
        else
            local ran
            ran, ok, done, reason = pcall(Migration.snapshotJob, state, job)
            if not ran then ok, reason = false, "snapshot_write_failed" end
            if ok and done then state.cursor = state.cursor + 1 end
        end
        if not ok then
            Migration.snapshotAbort(state)
            return false, false, reason
        end
        if budgetMs ~= nil then
            local now = startedAt ~= nil and Migration.transactionClock() or nil
            if now == nil or now < startedAt or now - startedAt >= budgetMs then return true, false end
        end
    end
end

local Salvage = {
    logLimit = 40,
    notices = {},
    shown = {},
    pending = {},
    sentTo = setmetatable({}, { __mode = "k" }),
}
ProjectALife.RecordSalvage = Salvage

Salvage.labels = { member = "NPC templates", faction = "factions" }

function Salvage.note(rejects, line, code, text, record)
    rejects[#rejects + 1] = { line = math.floor(tonumber(line) or 0), code = code,
        text = string.sub(tostring(text or ""), 1, 120), record = record }
end

function Salvage.records(text, kind)
    local rejects, source = {}, type(text) == "string" and text or ""
    if not ProjectALife.RecordMigration.isCurrent(source) then
        Salvage.note(rejects, 1, "retired_text", "")
        source = ""
    end
    local parsed = ProjectALife.RecordCodec.decode(source,
        { source = "salvage", kind = kind, text = true, lenient = true, rejects = rejects })
    local open = {}
    for _, reject in ipairs(rejects) do
        if reject.code == "unclosed_record" and reject.recordLine ~= nil then open[reject.recordLine] = true end
    end
    local kept, at = {}, {}
    for _, record in ipairs(parsed and parsed.records or {}) do
        if open[record.line] then

        elseif string.match(record.id, "^[%w_%-]+$") == nil then
            Salvage.note(rejects, record.line, "invalid_id", record.id, record.id)
        elseif at[record.id] ~= nil then
            Salvage.note(rejects, kept[at[record.id]].line, "duplicate_record", record.id, record.id)
            kept[at[record.id]] = record
        else
            kept[#kept + 1] = record
            at[record.id] = #kept
        end
    end
    return kept, rejects
end

function Salvage.profiles(text)
    local Custom, Codec = ProjectALife.CustomProfiles, ProjectALife.RecordCodec
    local records, rejects = Salvage.records(text, "member")
    for _, record in ipairs(records) do
        local probe, refused = Custom.blank(record.id), {}
        for section, values in pairs(record) do
            if type(values) == "table" then
                for key, value in pairs(values) do
                    if not Custom.applyField(probe, section, key, value) then
                        refused[#refused + 1] = { values, key, Codec.path("member", section, key) }
                    end
                end
            end
        end
        for _, entry in ipairs(refused) do
            entry[1][entry[2]] = nil
            Salvage.note(rejects, record.line, "refused_field", entry[3], record.id)
        end
    end
    local profiles = Custom.fromRecords(records, false)
    for _, profile in ipairs(profiles) do
        if Custom.checkAmmo({ profile }) == nil then
            local blank = Custom.blank(profile.id).general
            profile.general.ammoMode = blank.ammoMode
            profile.general.primaryMagazines = blank.primaryMagazines
            profile.general.secondaryMagazines = blank.secondaryMagazines
            Salvage.note(rejects, 0, "invalid_kit", "kit.ammoStyle", profile.id)
        end
    end
    return profiles, rejects
end

function Salvage.factions(text)
    local Custom = ProjectALife.CustomFactions
    local records, rejects = Salvage.records(text, "faction")
    for _, record in ipairs(records) do
        local refused = {}
        for section, values in pairs(record) do
            if type(values) == "table" and not Custom.typedSections[section] and not Custom.textSections[section] then
                refused[#refused + 1] = section
            end
        end
        for _, section in ipairs(refused) do
            record[section] = nil
            Salvage.note(rejects, record.line, "unknown_group", section, record.id)
        end
    end
    return Custom.fromRecords(records), rejects
end

function Salvage.items(text, kind)
    if kind == "member" then return Salvage.profiles(text) end
    return Salvage.factions(text)
end

function Salvage.log(kind, rejects, backup)
    local label = Salvage.labels[kind] or tostring(kind)
    for index, reject in ipairs(rejects) do
        if index > Salvage.logLimit then
            print("[A-Life] " .. label .. ": " .. tostring(#rejects - Salvage.logLimit) .. " more left out")
            break
        end
        print("[A-Life] " .. label .. ": left out line " .. tostring(reject.line) .. " (" .. tostring(reject.code) .. ")"
            .. (reject.record and (" in " .. tostring(reject.record)) or "") .. ": " .. tostring(reject.text))
    end
    if backup ~= nil then print("[A-Life] " .. label .. ": original kept in Zomboid/Lua/" .. tostring(backup)) end
end

function Salvage.noticeText(kind, rejects, backup)
    local first = rejects[1]
    local text = "Project A-Life: " .. tostring(#rejects) .. " damaged line(s) in the saved "
        .. (Salvage.labels[kind] or tostring(kind)) .. " were left out. Everything else loaded."
    if backup ~= nil then text = text .. "\nThe original is kept in Zomboid/Lua/" .. tostring(backup) .. "." end
    if first ~= nil then
        text = text .. "\nFirst: line " .. tostring(first.line) .. " (" .. tostring(first.code) .. ")"
            .. (first.record and (" in " .. tostring(first.record)) or "")
    end
    return text
end

function Salvage.report(kind, rejects, backup)
    Salvage.log(kind, rejects, backup)
    if #rejects == 0 then return nil end
    return Salvage.notify(Salvage.noticeText(kind, rejects, backup))
end

function Salvage.notify(text)
    if type(text) ~= "string" or text == "" then return nil end
    local known = false
    for _, notice in ipairs(Salvage.notices) do known = known or notice == text end
    if not known then Salvage.notices[#Salvage.notices + 1] = text end
    Salvage.showNotice(text)
    return text
end

function Salvage.isAdmin(player)
    if type(isServer) ~= "function" or not isServer() then return true end
    if player == nil or type(player.getAccessLevel) ~= "function" then return false end
    local ok, level = pcall(player.getAccessLevel, player)
    return ok and string.lower(tostring(level or "")) == "admin"
end

function Salvage.noticeFor(player)
    if player == nil then return nil end
    local sent = tonumber(Salvage.sentTo[player]) or 0
    if sent >= #Salvage.notices then return nil end
    if not Salvage.isAdmin(player) then return nil end
    Salvage.sentTo[player] = #Salvage.notices
    local parts = {}
    for index = sent + 1, #Salvage.notices do parts[#parts + 1] = Salvage.notices[index] end
    return table.concat(parts, "\n\n")
end

function Salvage.showNotice(text)
    if type(text) ~= "string" or text == "" or Salvage.shown[text] then return false end
    if type(isServer) == "function" and isServer() == true then return false end
    local dialog = ISModalDialog
    if type(dialog) ~= "table" or type(dialog.new) ~= "function" or type(getCore) ~= "function" then
        Salvage.wait(text)
        return false
    end
    Salvage.shown[text] = true
    local ok, failure = pcall(Salvage.openNotice, dialog, text)
    if not ok then print("[A-Life] record notice failed: " .. tostring(failure)) end
    return ok
end

function Salvage.wait(text)
    for _, waiting in ipairs(Salvage.pending) do
        if waiting == text then return false end
    end
    Salvage.pending[#Salvage.pending + 1] = text
    return true
end

function Salvage.showPending()
    local waiting = Salvage.pending
    if #waiting == 0 then return 0 end
    Salvage.pending = {}
    local shown = 0
    for _, text in ipairs(waiting) do
        if Salvage.showNotice(text) then shown = shown + 1 end
    end
    return shown
end

function Salvage.openNotice(dialog, text)
    local core = getCore()
    local width, height = 600, 180
    local modal = dialog:new(core:getScreenWidth() / 2 - width / 2, core:getScreenHeight() / 2 - height / 2,
        width, height, text, false, nil, nil, 0)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal:bringToTop()
end

function Salvage.restoreLocal(store, kind)
    local key = kind == "member" and "profiles" or "factions"
    if type(store) ~= "table" or #(store[key] or {}) > 0 then return false end
    local Migration = ProjectALife.RecordMigration
    local raw, readable = Migration.readFile(store.fileName)
    if not readable or type(raw) ~= "string" or string.find(raw, "%S") == nil then return false end
    local body = string.match(raw, "^@alife%-save %d+\n(.*)$") or raw
    body = string.gsub(body, "\n@alife%-save%-end$", "")
    if not Migration.isCurrent(body) then return Migration.setAside(store.fileName, raw) == true end
    local items, rejects = Salvage.items(body, kind)
    if #items == 0 then
        Salvage.log(kind, rejects, nil)
        return false
    end
    local kept, _, backup = Migration.keepOld(store.fileName, raw, Migration.badName)
    Salvage.report(kind, rejects, kept and backup or nil)
    store[key] = items
    if not kept then return false end
    store.loadFailed = false
    if type(store.persist) == "function" then store.persist() end
    return true
end

function Salvage.repairText(text, kind, serialize, validate)
    local items, rejects = Salvage.items(text, kind)
    local repaired = serialize(items)
    local checked = validate(repaired)
    if checked == nil or #checked ~= #items then return nil end
    return repaired, rejects
end

return Migration
