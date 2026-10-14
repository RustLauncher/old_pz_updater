KitsConfig = KitsConfig or {}

KitsConfig.Kits = {
    {
        id         = "basic",
        name       = "Supervivencia",
        icon       = "Base.BaseballBat",
        cooldown   = 360,
        permission = "all",
        items      = {
            { type = "Base.BaseballBat",      count = 1 },
            { type = "Base.WaterBottle",      count = 1 },
            { type = "Base.Apple",            count = 2 },
            { type = "Base.Bandage",          count = 2 },
        },
    },
    {
        id         = "medico",
        name       = "Medico",
        icon       = "Base.AlcoholBandage",
        cooldown   = 720,
        permission = "vip",
        items      = {
            { type = "Base.AlcoholBandage",   count = 10 },
            { type = "Base.Disinfectant",     count = 1 },
            { type = "Base.Pills",            count = 2 },
            { type = "Base.AlcoholWipes",     count = 2 },
            { type = "Base.SutureNeedle",     count = 1 },
            { type = "Base.Tweezers",         count = 1 },
            { type = "Base.Thread",           count = 1 },
        },
    },
    {
        id         = "combate",
        name       = "Combate CaC",
        icon       = "Base.Machete",
        cooldown   = 1440,
        permission = "vip",
        items      = {
            { type = "Base.Machete",           count = 1 },
            { type = "Base.WaterBottle",       count = 1 },
            { type = "Base.AlcoholBandage",    count = 4 },
            { type = "Base.AlcoholWipes",      count = 2 },
            { type = "Base.Pills",             count = 1 },
        },
    },
    {
        id         = "ropa",
        name       = "Ropa",
        icon       = "Base.Jacket_Padded",
        cooldown   = 1440,
        permission = "vip",
        items      = {
            { type = "Base.Jacket_Padded",        count = 1 },
            { type = "Base.Trousers_Denim",       count = 1 },
            { type = "Base.Shoes_WorkBoots",      count = 1 },
            { type = "Base.Gloves_LeatherGloves", count = 1 },
            { type = "Base.Hat_BaseballCap",      count = 1 },
            { type = "Base.Bag_BigHikingBag",     count = 1 },
        },
    },
    {
        id         = "armas",
        name       = "Armas",
        icon       = "Base.AssaultRifle",
        cooldown   = 2880,
        permission = "ultimate",
        items      = {
            { type = "Base.HuntingRifle",     count = 1 },
            { type = "Base.Pistol",           count = 1 },
            { type = "Base.Revolver",         count = 1 },
            { type = "Base.9mmClip",          count = 2 },
            { type = "Base.308Box",           count = 1 },
            { type = "Base.Bullets9mmBox",    count = 1 },
            { type = "Base.Bullets357Box",    count = 1 },
            { type = "Base.x2Scope",          count = 1 },
            { type = "Base.HolsterSimple",    count = 1 },
            { type = "Base.AlcoholBandage",   count = 2 },
        },
    },
    {
        id         = "equipo",
        name       = "Equipo Avanzado",
        icon       = "Base.Vest_BulletArmy",
        cooldown   = 2880,
        permission = "ultimate",
        items      = {
            { type = "Base.Vest_BulletArmy",      count = 1 },
            { type = "Base.Hat_Army",              count = 1 },
            { type = "Base.Bag_ALICEpack_Army",   count = 1 },
            { type = "Base.Boilersuit_SWAT",      count = 1 },
            { type = "Base.Gloves_LeatherGlovesBlack", count = 1 },
            { type = "Base.AssaultRifle",         count = 1 },
            { type = "Base.556Clip",              count = 2 },
            { type = "Base.556Box",               count = 1 },
        },
    },
    {
        id         = "generador",
        name       = "Generador",
        icon       = "Base.Generator",
        cooldown   = 10080,
        permission = "ultimate",
        items      = {
            { type = "Base.Generator",   count = 1 },
            { type = "Base.PetrolCan",   count = 4 },
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
