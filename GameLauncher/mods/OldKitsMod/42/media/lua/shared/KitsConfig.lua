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
        cooldown   = 360,
        permission = "vip",
        items      = {
            { type = "Base.AlcoholBandage",   count = 5 },
            { type = "Base.AlcoholWipes",     count = 2 },
            { type = "Base.Pills",            count = 1 },
            { type = "Base.Tweezers",         count = 1 },
            { type = "Base.SutureNeedle",     count = 1 },
        },
    },
    {
        id         = "combate",
        name       = "Combate CaC",
        icon       = "Base.BaseballBat_Metal",
        cooldown   = 1440,
        permission = "vip",
        items      = {
            { type = "Base.BaseballBat_Metal", count = 1 },
            { type = "Base.KitchenKnife",      count = 1 },
            { type = "Base.WaterBottle",       count = 1 },
            { type = "Base.Bandage",           count = 1 },
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
        },
    },
    {
        id         = "armas",
        name       = "Armas",
        icon       = "Base.Revolver",
        cooldown   = 1440,
        permission = "ultimate",
        items      = {
            { type = "Base.Revolver",      count = 1 },
            { type = "Base.Bullets357",    count = 6 },
            { type = "Base.Bandage",       count = 1 },
        },
    },
    {
        id         = "equipo",
        name       = "Equipo Avanzado",
        icon       = "Base.Vest_BulletCivilian",
        cooldown   = 1440,
        permission = "ultimate",
        items      = {
            { type = "Base.Vest_BulletCivilian",    count = 1 },
            { type = "Base.Hat_CrashHelmet",        count = 1 },
            { type = "Base.Bag_NormalHikingBag",    count = 1 },
            { type = "Base.Gloves_LeatherGloves",   count = 1 },
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
            { type = "Base.PetrolCan",   count = 1 },
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
