--[[
    KitsConfig.lua (shared)
    Define tus kits aqui. Ambos cliente y servidor cargan este archivo.

    Formato de cada kit:
        id          = identificador unico (string)
        name        = nombre visible en la UI
        icon        = textura del icono (item base del juego)
        cooldown    = cooldown en minutos (tiempo real)
        permission  = quien puede usar este kit:
                        "all"    = todos los jugadores
                        "admin"  = solo admins del servidor
                        "vip"    = jugadores con grupo "vip"
                        "donor"  = jugadores con grupo "donor"
                        (puedes inventar los grupos que quieras)
        items       = lista de { type = "Base.ItemName", count = cantidad }
]]

KitsConfig = KitsConfig or {}

KitsConfig.Kits = {
    {
        id         = "starter",
        name       = "Kit Inicial",
        icon       = "Base.Hammer",
        cooldown   = 30,
        permission = "all",
        items      = {
            { type = "Base.Hammer",          count = 1 },
            { type = "Base.Nails",           count = 20 },
            { type = "Base.Plank",           count = 5 },
            { type = "Base.Bandage",         count = 3 },
            { type = "Base.WaterBottleFull", count = 1 },
            { type = "Base.CannedBeans",     count = 2 },
        },
    },
    {
        id         = "combate",
        name       = "Kit de Combate",
        icon       = "Base.Axe",
        cooldown   = 60,
        permission = "all",
        items      = {
            { type = "Base.Axe",             count = 1 },
            { type = "Base.BaseballBat",     count = 1 },
            { type = "Base.Bandage",         count = 5 },
            { type = "Base.PillsVitamins",   count = 1 },
        },
    },
    {
        id         = "medico",
        name       = "Kit Medico",
        icon       = "Base.FirstAidKit",
        cooldown   = 45,
        permission = "vip",
        items      = {
            { type = "Base.FirstAidKit",     count = 1 },
            { type = "Base.Bandage",         count = 10 },
            { type = "Base.AlcoholBandage",  count = 5 },
            { type = "Base.SutureNeedle",    count = 2 },
            { type = "Base.PillsAntiDep",    count = 1 },
            { type = "Base.PillsVitamins",   count = 1 },
        },
    },
    {
        id         = "constructor",
        name       = "Kit Constructor",
        icon       = "Base.Saw",
        cooldown   = 90,
        permission = "admin",
        items      = {
            { type = "Base.Saw",             count = 1 },
            { type = "Base.Hammer",          count = 1 },
            { type = "Base.Screwdriver",     count = 1 },
            { type = "Base.Nails",           count = 50 },
            { type = "Base.Plank",           count = 15 },
            { type = "Base.MetalBar",        count = 3 },
        },
    },
}

function KitsConfig.GetKitById(kitId)
    for _, kit in ipairs(KitsConfig.Kits) do
        if kit.id == kitId then
            return kit
        end
    end
    return nil
end
