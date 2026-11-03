require "ProjectALife/Records/ALifeRecordCodec"

ProjectALife = ProjectALife or {}

local Parser = {}
ProjectALife.CatalogParser = Parser

function Parser.parseText(text, source, kind)
    if type(text) ~= "string" then return nil, "catalog_text_required" end
    source = tostring(source or "catalog")
    local parsed, reason = ProjectALife.RecordCodec.decode(text, { source = source, kind = kind })
    if parsed == nil then return nil, reason end
    if #parsed.records == 0 then return nil, source .. ":0:no_records" end
    return parsed
end

return Parser
