ProjectALife = ProjectALife or {}

local Names = {
    settings = { introductions = true, nicknameEvery = 25, probes = 64, firstProbes = 24, maxLength = 40 },
    index = nil,
    metrics = { assigned = 0, fixed = 0, firstReused = 0, fullReused = 0, backfilled = 0 },
    modes = { auto = true, male = true, female = true, fixed = true },
}
ProjectALife.Names = Names

Names.male = {
    "Aaron", "Adam", "Alan", "Albert", "Alfred", "Alvin", "Andre", "Andrew", "Anthony", "Antonio", "Arnold", "Arthur",
    "Barry", "Benjamin", "Bennie", "Bernard", "Billy", "Bobby", "Boyd", "Bradley", "Brandon", "Brent", "Brian", "Bruce",
    "Bryan", "Buford", "Byron", "Calvin", "Carl", "Carlos", "Cecil", "Chad", "Charles", "Chester", "Christopher",
    "Clarence", "Claude", "Clayton", "Clifford", "Clinton", "Clyde", "Cody", "Cornelius", "Craig", "Curtis", "Dale",
    "Dallas", "Damon", "Daniel", "Darnell", "Darrell", "Darren", "Darryl", "David", "Dean", "Delbert", "Dennis", "Derek",
    "Derrick", "Dewey", "Dominic", "Donald", "Donnie", "Douglas", "Duane", "Dustin", "Dwayne", "Dwight", "Earl", "Eddie",
    "Edgar", "Edward", "Edwin", "Elijah", "Elmer", "Emmett", "Eric", "Ernest", "Eugene", "Everett", "Floyd", "Francis",
    "Frank", "Franklin", "Fred", "Gary", "Gene", "George", "Gerald", "Gilbert", "Glenn", "Gordon", "Grady", "Gregory",
    "Harlan", "Harold", "Harvey", "Hector", "Henry", "Herbert", "Herman", "Homer", "Howard", "Hubert", "Hugh", "Isaac",
    "Ivan", "Jack", "Jacob", "Jamal", "James", "Jared", "Jason", "Jeffrey", "Jeremy", "Jerome", "Jerry", "Jesse",
    "Jimmy", "Joe", "Joel", "John", "Johnny", "Jonathan", "Jorge", "Jose", "Joseph", "Joshua", "Juan", "Julian",
    "Justin", "Keith", "Kenneth", "Kenny", "Kevin", "Kirk", "Kyle", "Lamar", "Lance", "Larry", "Lawrence", "Lee",
    "Leon", "Leonard", "Leroy", "Lester", "Lewis", "Lloyd", "Lonnie", "Louis", "Lowell", "Luis", "Luther", "Malcolm",
    "Manuel", "Marcus", "Mario", "Mark", "Marshall", "Martin", "Marvin", "Matthew", "Maurice", "Melvin", "Michael",
    "Miguel", "Mitchell", "Morris", "Nathan", "Neal", "Nelson", "Nicholas", "Noah", "Norman", "Oliver", "Orville",
    "Oscar", "Otis", "Patrick", "Paul", "Pedro", "Perry", "Peter", "Phillip", "Quentin", "Ralph", "Ramon", "Randall",
    "Randy", "Raymond", "Reginald", "Ricky", "Robert", "Rodney", "Roger", "Roland", "Ronald", "Roscoe", "Roy",
    "Russell", "Ryan", "Samuel", "Scott", "Sean", "Shane", "Shawn", "Sherman", "Stanley", "Stephen", "Steven",
    "Terrence", "Terry", "Theodore", "Thomas", "Timothy", "Todd", "Tommy", "Tony", "Travis", "Trent", "Troy", "Tyrone",
    "Victor", "Vincent", "Virgil", "Wade", "Walter", "Warren", "Wayne", "Wendell", "Wesley", "Wilbur", "Willard",
    "William", "Willie", "Woodrow", "Zachary", "Tuan", "Minh", "Omar", "Hassan", "Dmitri", "Stefan", "Kenji", "Rajesh",
    "Ezekiel", "Amos", "Jasper", "Silas", "Ricardo", "Javier", "Desmond", "Rufus", "Ellis", "Irvin", "Mack", "Sonny",
}

Names.female = {
    "Abigail", "Adrienne", "Alice", "Alicia", "Allison", "Alma", "Amanda", "Amber", "Amy", "Andrea", "Angela", "Anita",
    "Ann", "Anna", "Annette", "April", "Arlene", "Audrey", "Barbara", "Beatrice", "Becky", "Belinda", "Bernice", "Beth",
    "Betty", "Beverly", "Bonnie", "Brandy", "Brenda", "Brittany", "Candace", "Carla", "Carmen", "Carol", "Caroline",
    "Carolyn", "Carrie", "Cassandra", "Catherine", "Cathy", "Cecilia", "Charlene", "Charlotte", "Cheryl", "Christina",
    "Christine", "Cindy", "Claire", "Claudia", "Connie", "Constance", "Courtney", "Crystal", "Cynthia", "Daisy", "Dana",
    "Danielle", "Darlene", "Dawn", "Debbie", "Deborah", "Delores", "Denise", "Diana", "Diane", "Dolly", "Donna", "Doris",
    "Dorothy", "Edna", "Eileen", "Elaine", "Eleanor", "Elizabeth", "Ella", "Ellen", "Emily", "Erica", "Erin", "Esther",
    "Ethel", "Eva", "Evelyn", "Faye", "Florence", "Frances", "Gail", "Geneva", "Georgia", "Geraldine", "Gina", "Gladys",
    "Glenda", "Gloria", "Grace", "Gwendolyn", "Hazel", "Heather", "Heidi", "Helen", "Holly", "Ida", "Imogene", "Irene",
    "Iris", "Jackie", "Jacqueline", "Jamie", "Jane", "Janet", "Janice", "Jasmine", "Jean", "Jeanette", "Jennifer",
    "Jessica", "Jill", "Joan", "Joann", "Jodi", "Josephine", "Joy", "Joyce", "Juanita", "Judith", "Judy", "Julia",
    "Julie", "June", "Karen", "Kathleen", "Kathy", "Katie", "Kayla", "Kelly", "Kimberly", "Kristen", "Latasha", "Latoya",
    "Laura", "Lauren", "Laverne", "Leah", "Leslie", "Lillian", "Linda", "Lisa", "Lois", "Lorraine", "Louise", "Lucille",
    "Lucy", "Lydia", "Lynn", "Mabel", "Mamie", "Marcia", "Margaret", "Maria", "Marie", "Marilyn", "Marjorie", "Marlene",
    "Martha", "Mary", "Maxine", "Megan", "Melanie", "Melissa", "Michelle", "Mildred", "Minnie", "Miranda", "Misty",
    "Monica", "Nancy", "Naomi", "Natalie", "Nicole", "Nina", "Nora", "Norma", "Olivia", "Opal", "Pamela", "Patricia",
    "Paula", "Pauline", "Pearl", "Peggy", "Phyllis", "Priscilla", "Rachel", "Ramona", "Rebecca", "Regina", "Renee",
    "Rhonda", "Rita", "Roberta", "Robin", "Rosa", "Rose", "Rosemary", "Ruby", "Ruth", "Sabrina", "Sally", "Samantha",
    "Sandra", "Sara", "Sarah", "Shannon", "Sharon", "Sheila", "Shelby", "Sherry", "Shirley", "Sonya", "Stacy",
    "Stephanie", "Sue", "Susan", "Suzanne", "Sylvia", "Tamara", "Tammy", "Tanya", "Teresa", "Terri", "Thelma",
    "Tiffany", "Tina", "Toni", "Tonya", "Tracy", "Valerie", "Vanessa", "Vera", "Veronica", "Vicki", "Victoria", "Viola",
    "Violet", "Virginia", "Wanda", "Wilma", "Yolanda", "Yvonne", "Lan", "Mai", "Fatima", "Leila", "Guadalupe", "Ana",
    "Ingrid", "Greta", "Della", "Etta", "Lula", "Nell", "Oleta", "Reba", "Twila", "Verna", "Willa", "Zelda",
}

Names.surnames = {
    "Abbott", "Abernathy", "Absher", "Adams", "Adkins", "Akers", "Alexander", "Allen", "Alvarez", "Andersen",
    "Anderson", "Arnett", "Arnold", "Atkins", "Bailey", "Baird", "Baker", "Ball", "Banks", "Barker", "Barnes",
    "Bartley", "Bates", "Baxter", "Beasley", "Beck", "Becker", "Bell", "Bennett", "Berry", "Bishop", "Blackburn",
    "Blair", "Blanton", "Bledsoe", "Boggs", "Boone", "Bowling", "Bowman", "Boyd", "Bradley", "Brandenburg", "Branham",
    "Brewer", "Brock", "Brooks", "Brown", "Bryant", "Bui", "Burchett", "Burke", "Burns", "Bush", "Butler", "Byrne",
    "Caldwell", "Calhoun", "Campbell", "Cantrell", "Carmichael", "Carpenter", "Carr", "Carroll", "Carter", "Casey",
    "Castillo", "Castle", "Caudill", "Chandler", "Chaney", "Chapman", "Childers", "Choi", "Clark", "Clay", "Click",
    "Cline", "Cobb", "Coffey", "Cole", "Coleman", "Collins", "Colvin", "Combs", "Compton", "Conley", "Cook", "Cooper",
    "Cornett", "Costa", "Couch", "Cox", "Crabtree", "Craft", "Crawford", "Crisp", "Cross", "Cummins", "Cundiff",
    "Dalton", "Dameron", "Daniels", "Davidson", "Davis", "Day", "Deaton", "Delgado", "Dennis", "Dietrich", "Dixon",
    "Dotson", "Doyle", "Duarte", "Duncan", "Dunn", "Durham", "Dyer", "Edwards", "Elam", "Elliott", "Ellis",
    "Esposito", "Estep", "Evans", "Everage", "Eversole", "Fannin", "Farmer", "Faulkner", "Ferguson", "Fielder",
    "Fields", "Fischer", "Fitzgerald", "Fleming", "Fletcher", "Flores", "Ford", "Foster", "Fox", "Francis",
    "Franklin", "Frazier", "Frye", "Fugate", "Fuller", "Gabbard", "Gaines", "Gallagher", "Garcia", "Gardner",
    "Garrett", "Gibson", "Gilbert", "Gillespie", "Gilliam", "Goff", "Goins", "Goldstein", "Gonzalez", "Goodman",
    "Graham", "Gray", "Green", "Gregory", "Griffin", "Griffith", "Grimes", "Gross", "Gullett", "Hacker", "Haddad",
    "Hager", "Hale", "Hall", "Hamilton", "Hammond", "Hammons", "Hampton", "Hardin", "Harper", "Harris", "Hart",
    "Hatfield", "Hatton", "Hawkins", "Hayes", "Helton", "Henderson", "Hensley", "Hernandez", "Hicks", "Hill",
    "Hoffman", "Holbrook", "Holland", "Hollon", "Holt", "Honaker", "Hopkins", "Horn", "Howard", "Howell", "Hubbard",
    "Hudson", "Huff", "Hughes", "Hunt", "Hurley", "Ingram", "Isaacs", "Jackson", "James", "Jarvis", "Jenkins",
    "Jimenez", "Johnson", "Johnston", "Jones", "Jordan", "Justice", "Kaminski", "Keeton", "Keller", "Kelly",
    "Kendrick", "Kennedy", "Khan", "Kidd", "Kilgore", "Kim", "Kincaid", "King", "Kirby", "Knight", "Kowalczyk",
    "Kowalski", "Lambert", "Lane", "Lawson", "Le", "Lee", "Lewis", "Lindqvist", "Little", "Logan", "Long", "Lopez",
    "Lucas", "Lykins", "Lynch", "Maddox", "Maggard", "Mahoney", "Mann", "Marcum", "Marshall", "Martin", "Martinez",
    "Mason", "Mattingly", "May", "Mayes", "McCoy", "McDaniel", "McGuire", "McIntosh", "McKinney", "Meade", "Medina",
    "Melton", "Mendoza", "Mensah", "Mercer", "Messer", "Meyer", "Miller", "Mills", "Mitchell", "Moore", "Moretti",
    "Morgan", "Morris", "Moses", "Mosley", "Mounts", "Mullins", "Murphy", "Murray", "Napier", "Navarro", "Neal",
    "Nelson", "Newsome", "Nguyen", "Nichols", "Noble", "Noe", "Novak", "O'Brien", "O'Neal", "Ochoa", "Okafor",
    "Olsen", "Ortiz", "Osborne", "Owens", "Park", "Parker", "Parsons", "Patel", "Patrick", "Patton", "Payne",
    "Pearson", "Pennington", "Perkins", "Perry", "Peters", "Petrov", "Pham", "Phillips", "Pierce", "Pigg", "Polly",
    "Pope", "Porter", "Potter", "Powell", "Prater", "Pratt", "Preston", "Price", "Puckett", "Quinn", "Rader",
    "Ramirez", "Ramsey", "Ratliff", "Ray", "Reed", "Reynolds", "Rice", "Richards", "Richardson", "Riley", "Ritchie",
    "Rivera", "Roark", "Roberts", "Robinson", "Rodriguez", "Rogers", "Romano", "Rosenberg", "Ross", "Rowe", "Rudd",
    "Ruiz", "Russell", "Russo", "Salyers", "Sanders", "Saylor", "Schmidt", "Schneider", "Scott", "Sexton", "Shepherd",
    "Short", "Silva", "Simmons", "Simpson", "Sizemore", "Skaggs", "Slone", "Smith", "Sparks", "Spears", "Spencer",
    "Stacy", "Stamper", "Stanley", "Stephens", "Stevens", "Stewart", "Stidham", "Stone", "Sullivan", "Sutton",
    "Swafford", "Taylor", "Terry", "Thacker", "Thomas", "Thompson", "Tipton", "Tolliver", "Townsend", "Tran", "Trent",
    "Tucker", "Turner", "Turpin", "Underwood", "Vance", "Vanover", "Vaughn", "Vires", "Vo", "Wagner", "Walker",
    "Wallace", "Walters", "Ward", "Warren", "Washington", "Watkins", "Watson", "Watts", "Weaver", "Webb", "Weber",
    "Wells", "West", "Wheeler", "Whitaker", "White", "Wiggins", "Wilder", "Williams", "Williamson", "Willis",
    "Wilson", "Wireman", "Wolfe", "Wood", "Woods", "Wright", "Yamamoto", "Yates", "Yonts", "Young", "Zeller",
    "Zimmerman",
}

Names.nicknames = {
    male = { "Red", "Buck", "Doc", "Skeeter", "Tex", "Lucky", "Moose", "Slim", "Shorty", "Cotton", "Duke", "Junior",
        "Smitty", "Bear", "Ace", "Butch", "Rusty", "Catfish", "Hoss", "Tiny" },
    female = { "Red", "Dot", "Sissy", "Birdie", "Peaches", "Sunny", "Ginger", "Dixie", "Lucky", "Jojo", "Missy",
        "Tootie", "Pinky", "Babe" },
}

Names.introLines = {
    any = {
        "Name's {myfirst}. {myfirst} {mylast}.",
        "{myfirst}. Pleased to meet you, I guess, all things considered.",
        "I'm {myfirst} {mylast}. Was, anyway. Still am, I suppose.",
        "Folks call me {myfirst}. You can too.",
        "{myfirst} {mylast}. From up the road, what's left of it.",
        "It's {myfirst}. Try not to wear it out.",
        "{myfirst}. Last name's {mylast}, if we're being proper about it.",
        "Call me {myfirst}. Everybody did, back when there was an everybody.",
        "{myfirst} {mylast}. Nice to hear somebody ask.",
    },
    law = {
        "{mylast}. I had it on a badge until about a week ago.",
        "It's {mylast}. {myfirst} when I'm off the clock, and nobody's on the clock anymore.",
        "{myfirst} {mylast}, county. What's left of the county.",
    },
    military = {
        "{mylast}. {myfirst} {mylast}. Old habit, last name first.",
        "{mylast} will do. First name's {myfirst}, but nobody's used it since basic.",
        "{myfirst} {mylast}. My unit's gone, so I guess it's just the name now.",
    },
    rough = {
        "{myfirst}. That's all you're getting.",
        "{myfirst}. Remember it, in case somebody asks who let you walk.",
        "Name's {myfirst}. Don't go spreading it around.",
    },
}

Names.refuseLines = {
    "Let's skip names for now.",
    "You don't need my name to keep your distance.",
    "Names come later. If there's a later.",
    "Not yet. Stay right where you are.",
    "Ask me again when I know what you're about.",
}

Names.registerGroups = {
    law = "law", swat = "law", military = "military", elite = "military",
    outlaw = "rough", raider = "rough", gang = "rough", club = "rough", prison = "rough", crime = "rough",
}

function Names.mix(value)
    value = math.floor(math.abs(tonumber(value) or 0)) % 2147483647
    if value == 0 then value = 1 end
    for _ = 1, 3 do value = (value * 48271) % 2147483647 end
    return value
end

function Names.hash(text)
    local value = 7
    text = tostring(text or "")
    for index = 1, #text do value = (value * 31 + string.byte(text, index)) % 2147483647 end
    return Names.mix(value)
end

function Names.clean(text)
    if type(text) == "number" then text = tostring(text) end
    if type(text) ~= "string" then return "" end
    text = string.gsub(text, "[%c<>\"]", " ")
    text = string.gsub(text, "%s+", " ")
    text = string.match(text, "^%s*(.-)%s*$") or ""
    if #text > Names.settings.maxLength then text = string.sub(text, 1, Names.settings.maxLength) end
    return text
end

function Names.split(text)
    text = Names.clean(text)
    if text == "" then return nil, nil end
    local first, rest = string.match(text, "^(%S+)%s+(.+)$")
    if first == nil then return text, "" end
    return first, rest
end

function Names.compose(first, last, nick)
    local text = tostring(first or "")
    if nick ~= nil and nick ~= "" then text = text .. " \"" .. nick .. "\"" end
    if last ~= nil and last ~= "" then text = text .. " " .. last end
    return text
end

function Names.modeOf(general)
    local mode = type(general) == "table" and general.nameMode or nil
    mode = type(mode) == "string" and string.lower(mode) or "auto"
    if not Names.modes[mode] then mode = "auto" end
    if mode == "fixed" and Names.clean(general.fixedName) == "" then mode = "auto" end
    return mode
end

function Names.generalFor(profileId)
    local catalog = ProjectALife.Catalog
    if catalog == nil or type(catalog.npc) ~= "function" or profileId == nil then return nil end
    local ok, profile = pcall(catalog.npc, profileId)
    if not ok or type(profile) ~= "table" or type(profile.general) ~= "table" then return nil end
    return profile.general
end

function Names.key(first, last)
    return string.lower(tostring(first or "") .. " " .. tostring(last or ""))
end

function Names.note(index, first, last)
    if type(index) ~= "table" or first == nil then return end
    local lower = string.lower(tostring(first))
    index.first[lower] = (index.first[lower] or 0) + 1
    index.full[Names.key(first, last)] = true
end

function Names.indexFor(records)
    local index = Names.index
    if index ~= nil and index.source == records then return index end
    index = { source = records, full = {}, first = {} }
    if type(records) == "table" then
        for _, record in pairs(records) do
            local memory = type(record) == "table" and record.memory or nil
            if type(memory) == "table" and type(memory.personFirst) == "string" then
                Names.note(index, memory.personFirst, memory.personLast)
            end
        end
    end
    Names.index = index
    return index
end

function Names.draw(seed, female, index)
    local firsts = female == true and Names.female or Names.male
    local lasts = Names.surnames
    local fallbackFirst, fallbackLast
    for attempt = 0, Names.settings.probes - 1 do
        local value = Names.mix(seed + attempt * 7919)
        local first = firsts[value % #firsts + 1]
        local last = lasts[math.floor(value / #firsts) % #lasts + 1]
        if index == nil or not index.full[Names.key(first, last)] then
            if index == nil or (index.first[string.lower(first)] or 0) == 0 then return first, last end
            if fallbackFirst == nil then fallbackFirst, fallbackLast = first, last end
            if attempt >= Names.settings.firstProbes then
                Names.metrics.firstReused = Names.metrics.firstReused + 1
                return fallbackFirst, fallbackLast
            end
        end
    end
    if fallbackFirst ~= nil then
        Names.metrics.firstReused = Names.metrics.firstReused + 1
        return fallbackFirst, fallbackLast
    end
    Names.metrics.fullReused = Names.metrics.fullReused + 1
    local value = Names.mix(seed + 104723)
    local letters = "ABCDEFGHJKLMNPRSTW"
    local initial = string.sub(letters, value % #letters + 1, value % #letters + 1)
    return firsts[value % #firsts + 1], initial .. ". " .. lasts[math.floor(value / #firsts) % #lasts + 1]
end

function Names.nicknameFor(seed, female)
    local every = math.max(1, math.floor(tonumber(Names.settings.nicknameEvery) or 25))
    local value = Names.mix(seed + 104729)
    if value % every ~= 0 then return nil end
    local pool = female == true and Names.nicknames.female or Names.nicknames.male
    return pool[math.floor(value / every) % #pool + 1]
end

function Names.assign(record, records)
    if type(record) ~= "table" then return nil end
    if type(record.memory) ~= "table" then record.memory = {} end
    local memory = record.memory
    if type(memory.personName) == "string" and memory.personName ~= "" then return memory.personName end
    local general = Names.generalFor(record.profileId)
    local mode = Names.modeOf(general)
    local index = Names.indexFor(records)
    local seed = Names.hash(record.uid)
    local first, last, nick
    if mode == "fixed" then
        first, last = Names.split(general.fixedName)
        Names.metrics.fixed = Names.metrics.fixed + 1
    end
    if first == nil then
        local female
        if mode == "female" then female = true
        elseif mode == "male" then female = false
        elseif type(general) == "table" and general.female ~= nil then female = general.female == true or general.female == "true"
        else female = seed % 2 == 1 end
        first, last = Names.draw(seed, female, index)
        nick = Names.nicknameFor(seed, female)
    end
    memory.personFirst, memory.personLast = first, last
    memory.personName = Names.compose(first, last, nick)
    Names.note(index, first, last)
    Names.metrics.assigned = Names.metrics.assigned + 1
    return memory.personName
end

function Names.backfill(order, records)
    local named = 0
    if type(order) ~= "table" or type(records) ~= "table" then return 0 end
    for _, uid in ipairs(order) do
        local record = records[uid]
        local memory = type(record) == "table" and record.memory or nil
        if type(record) == "table" and (type(memory) ~= "table" or type(memory.personName) ~= "string") then
            if Names.assign(record, records) ~= nil then named = named + 1 end
        end
    end
    Names.metrics.backfilled = Names.metrics.backfilled + named
    return named
end

function Names.of(record)
    local memory = type(record) == "table" and record.memory or nil
    if type(memory) ~= "table" or type(memory.personName) ~= "string" or memory.personName == "" then return nil end
    return memory.personName
end

function Names.knows(record, playerKey)
    if Names.settings.introductions ~= true then return true end
    local memory = type(record) == "table" and record.memory or nil
    local met = type(memory) == "table" and memory.introducedTo or nil
    return playerKey ~= nil and type(met) == "table" and met[tostring(playerKey)] == true
end

function Names.shown(record, playerKey)
    local name = Names.of(record)
    if name == nil then return nil, false end
    if not Names.knows(record, playerKey) then return nil, false end
    return name, true
end

function Names.markIntroduced(memory, playerKey)
    if type(memory) ~= "table" or playerKey == nil then return false end
    memory.introducedTo = type(memory.introducedTo) == "table" and memory.introducedTo or {}
    memory.introducedTo[tostring(playerKey)] = true
    return true
end

function Names.role(label)
    if type(label) ~= "string" then return nil end
    local role = string.match(label, "^.-%s+%-%s+(.+)$")
    if role == nil or role == "" then return nil end
    return role
end

function Names.introPool(register)
    local group = Names.registerGroups[tostring(register or "")]
    return Names.introLines[group or "any"] or Names.introLines.any
end

function Names.vars(record)
    local memory = type(record) == "table" and type(record.memory) == "table" and record.memory or {}
    local first, last = tostring(memory.personFirst or ""), tostring(memory.personLast or "")
    if last == "" then last = first end
    return { myfirst = first, mylast = last, myname = Names.compose(first, memory.personLast) }
end

function Names.reset()
    Names.index = nil
    Names.metrics = { assigned = 0, fixed = 0, firstReused = 0, fullReused = 0, backfilled = 0 }
end

return Names
