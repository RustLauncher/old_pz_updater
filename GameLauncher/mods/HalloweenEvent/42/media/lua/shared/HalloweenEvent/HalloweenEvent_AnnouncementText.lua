-- Plain admin text shared by the authoritative announcement and its presentation.
HalloweenEvent = HalloweenEvent or {}
local T = {}
HalloweenEvent.AnnouncementText = T
T.default = "The Halloween Event has Started"
T.endDefault = "The Halloween Event has Ended"

function T.characters(text)
    local chars = {}
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        chars[#chars + 1] = char
    end
    return chars
end

function T.clean(value,kind)
    local default = kind=="end" and T.endDefault or T.default
    local text = type(value)=="string" and value or default
    text = text:gsub("[%z\1-\31\127]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    -- Native Sandbox string defaults preserve quote characters. Repair only
    -- the old quoted default; deliberate quotes in a custom message stay.
    if text=='"'..default..'"' or text=="'"..default.."'" then text=default end
    if text=="" then return default end
    -- Bound the network payload without cutting a UTF-8 character in half.
    if #text>4096 then
        local chars, count, kept = T.characters(text), 0, {}
        for _, char in ipairs(chars) do
            if count+#char>4093 then break end
            kept[#kept+1], count = char, count+#char
        end
        text = table.concat(kept).."..."
    end
    return text
end

function T.chatLine(text)
    -- Use the same entity escaping as native ChatMessage; admin text stays plain.
    return "<RGB:1,0.55,0.12> [Server] "..text:gsub("<", "&lt;"):gsub(">", "&gt;").." <RGB:1,1,1>"
end
return T
