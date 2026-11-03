require "ProjectALife/Visitors/ALifeVisitorSchema"
require "ProjectALife/Visitors/ALifeVisitorPeople"
require "ProjectALife/Visitors/ALifeVisitorInstance"
require "ProjectALife/Visitors/ALifeVisitorTalkRules"

ProjectALife = ProjectALife or {}

local Schema = ProjectALife.VisitorSchema
local People = ProjectALife.VisitorPeople
local Instance = ProjectALife.VisitorInstance
local Rules = ProjectALife.VisitorTalkRules

local Books = {
    metrics = { answers = 0, lent = 0, missing = 0 },
    keys = {
        VQ_BOOK_ABOUT = "about", VQ_BOOK_WHY = "why", VQ_BOOK_LIKE = "like", VQ_BOOK_ENDING = "ending",
        VQ_BOOK_CHARACTER = "character", VQ_BOOK_HARD = "hard", VQ_BOOK_AGAIN = "again", VQ_BOOK_LEND = "lend",
    },
}
ProjectALife.VisitorBooks = Books

function Books.enabled(env)
    return Rules.options().books == true
end

function Books.current(env)
    local card = Rules.card(env)
    if card == nil or not Books.enabled(env) then return nil end
    local id = card.books.current
    if id == nil and #card.books.reads > 0 then id = card.books.reads[1] end
    if id == nil then return nil end
    local book = People.book(id)
    return book
end

function Books.has(env)
    return Books.current(env) ~= nil
end

function Books.liked(book, card)
    for _, id in ipairs(card.books.reads) do
        if id == book.id then return true end
    end
    for _, taste in ipairs(card.books.taste) do
        if book.genre ~= nil and (taste == book.genre or taste .. "s" == book.genre or taste == book.genre .. "s") then return true end
    end
    return false
end

function Books.slot(env, name)
    local book = Books.current(env)
    if book == nil then return nil end
    if name == "book" then return book.title end
    if name == "author" then return book.author end
    return nil
end

function Books.variants(raw, key, set)
    local group = type(raw.a) == "table" and raw.a[key] or nil
    local list = type(group) == "table" and group[set] or nil
    if type(list) ~= "table" then return {} end
    return Schema.texts(list)
end

function Books.answer(env, questionId, count)
    local key = Books.keys[questionId]
    local book = Books.current(env)
    local card = Rules.card(env)
    if key == nil or book == nil or card == nil then return nil end
    local liked = Books.liked(book, card)
    local order = liked and { "like", "any", "dislike" } or { "dislike", "any", "like" }
    for position = 1, #order do
        local list = Books.variants(book.raw, key, order[position])
        if #list > 0 then
            Books.metrics.answers = Books.metrics.answers + 1
            local index = (count % #list) + 1
            return list[index], index, order[position]
        end
    end
    Books.metrics.missing = Books.metrics.missing + 1
    return nil
end

function Books.lend(env, row, extra)
    local liked = extra ~= nil and extra.liked == true
    local book = Books.current(env)
    local card = Rules.card(env)
    if book ~= nil and card ~= nil and extra ~= nil and extra.bookId == book.id then liked = Books.liked(book, card) end
    Instance.setFlag(row, "lent_book")
    Books.metrics.lent = Books.metrics.lent + 1
    return liked
end

function Books.qaLine()
    local m = Books.metrics
    return "[ALIFE-QA] VisitorBooks answers=" .. tostring(m.answers) .. " lent=" .. tostring(m.lent)
        .. " missing=" .. tostring(m.missing)
end

return Books
