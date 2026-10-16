ProjectALife = ProjectALife or {}

local Transfer = {
    chunkChars = 8000,
    profileLimit = 8000000,
    factionLimit = 2000000,
    timeoutMs = 60000,
    maximumActive = 8,
    serial = 0,
    pending = setmetatable({}, { __mode = "k" }),
    completed = setmetatable({}, { __mode = "k" }),
}
ProjectALife.CreatorTransfer = Transfer

function Transfer.integer(value, minimum, maximum)
    return type(value) == "number" and value == value and value >= minimum
        and value <= maximum and value == math.floor(value)
end

function Transfer.validId(value)
    return type(value) == "string" and #value > 0 and #value <= 128
        and string.match(value, "^[%w_%-]+$") ~= nil
end

function Transfer.shape(kind, profileSize, factionSize, recordId)
    if not Transfer.integer(profileSize, 0, Transfer.profileLimit)
            or not Transfer.integer(factionSize, 0, Transfer.factionLimit) then
        return false
    end
    if kind == "replace" then return recordId == nil end
    if not Transfer.validId(recordId) then return false end
    return (kind == "profile" and profileSize > 0 and factionSize == 0)
        or (kind == "faction" and factionSize > 0 and profileSize == 0)
end

function Transfer.split(text)
    local parts, first = {}, 1
    while first <= #text do
        local last = math.min(#text, first + Transfer.chunkChars - 1)
        local edge = string.byte(text, last)
        if last < #text and edge >= 55296 and edge <= 56319 then last = last - 1 end
        parts[#parts + 1] = string.sub(text, first, last)
        first = last + 1
    end
    return parts
end

function Transfer.send(player, kind, profiles, factions, recordId)
    if player == nil or type(sendClientCommand) ~= "function" then return false, "creator_sender_unavailable" end
    if type(profiles) ~= "string" or type(factions) ~= "string"
            or not Transfer.shape(kind, #profiles, #factions, recordId) then
        return false, "creator_payload_invalid_or_too_large"
    end
    Transfer.serial = Transfer.serial + 1
    local stamp = type(getTimestampMs) == "function" and getTimestampMs() or 0
    local id = string.format("%.0f", stamp) .. "-" .. tostring(Transfer.serial)
    local text = profiles .. factions
    local parts = Transfer.split(text)
    if #parts == 0 then parts[1] = "" end
    local total = #parts
    for index = 1, total do
        local ok, result = pcall(sendClientCommand, player, "ProjectALife", "creatorUpload", {
            schema = 1, transfer = id, kind = kind, recordId = recordId,
            profileSize = #profiles, factionSize = #factions, index = index, total = total,
            text = parts[index],
        })
        if not ok or result == false then return false, "creator_upload_send_failed" end
    end
    return true
end

function Transfer.receive(player, args, now)
    if player == nil or type(args) ~= "table" or args.schema ~= 1
            or not Transfer.validId(args.transfer)
            or not Transfer.shape(args.kind, args.profileSize, args.factionSize, args.recordId)
            or type(args.text) ~= "string" or #args.text > Transfer.chunkChars then
        return nil, "creator_upload_invalid"
    end
    local size = args.profileSize + args.factionSize
    local total = args.total
    if not Transfer.integer(total, math.max(1, math.ceil(size / Transfer.chunkChars)),
                math.max(1, math.ceil(size / (Transfer.chunkChars - 1))))
            or not Transfer.integer(args.index, 1, total) then
        return nil, "creator_upload_shape"
    end
    if (size > 0 and #args.text == 0) or (size == 0 and #args.text ~= 0)
            or (args.index < total and #args.text < Transfer.chunkChars - 1) then
        return nil, "creator_upload_length"
    end
    now = tonumber(now) or 0
    local active = 0
    for owner, upload in pairs(Transfer.pending) do
        if upload.expires <= now then Transfer.pending[owner] = nil else active = active + 1 end
    end
    local upload = Transfer.pending[player]
    if upload == nil then
        if Transfer.completed[player] == args.transfer then return nil, "creator_upload_replayed" end
        if args.index ~= 1 then return nil, "creator_upload_start_required" end
        if active >= Transfer.maximumActive then return nil, "creator_upload_busy" end
        upload = { id = args.transfer, kind = args.kind, recordId = args.recordId,
            profileSize = args.profileSize, factionSize = args.factionSize,
            total = total, count = 0, size = 0, parts = {}, expires = now + Transfer.timeoutMs }
        Transfer.pending[player] = upload
    elseif upload.id ~= args.transfer then
        return nil, "creator_upload_busy"
    end
    if upload.kind ~= args.kind or upload.recordId ~= args.recordId
            or upload.profileSize ~= args.profileSize or upload.factionSize ~= args.factionSize
            or upload.total ~= total then
        Transfer.pending[player] = nil
        return nil, "creator_upload_changed"
    end
    local previous = upload.parts[args.index]
    if previous ~= nil and previous ~= args.text then
        Transfer.pending[player] = nil
        return nil, "creator_upload_changed"
    end
    if previous == nil then
        upload.parts[args.index] = args.text
        upload.count, upload.size = upload.count + 1, upload.size + #args.text
        if upload.size > size then Transfer.pending[player] = nil; return nil, "creator_upload_length" end
    end
    if upload.count ~= total then return false, "partial" end
    Transfer.pending[player] = nil
    local combined = table.concat(upload.parts)
    if #combined ~= size then return nil, "creator_upload_length" end
    Transfer.completed[player] = upload.id
    return { kind = upload.kind, recordId = upload.recordId,
        profiles = string.sub(combined, 1, upload.profileSize),
        factions = string.sub(combined, upload.profileSize + 1) }
end

function Transfer.join(chunks, limit)
    if type(chunks) ~= "table" then return nil, "creator_chunks_required" end
    local count, maximum, size = 0, 0, 0
    for index, part in pairs(chunks) do
        if not Transfer.integer(index, 1, math.ceil(limit / (Transfer.chunkChars - 1)))
                or type(part) ~= "string" or #part > Transfer.chunkChars then
            return nil, "creator_chunks_invalid"
        end
        count, maximum, size = count + 1, math.max(maximum, index), size + #part
        if size > limit then return nil, "creator_payload_too_large" end
    end
    if count ~= maximum then return nil, "creator_chunks_incomplete" end
    return table.concat(chunks)
end

return Transfer
