DDV01 = DDV01 or {}
local D = DDV01
D.VERSION = "1.1.0"
D.MODULE = "WhiteDoorDamageTest"
D.DATA_KEY = "DDV01_Test"
D.MODEL_PREFIX = "ct_white_door_test_"
D.FAMILIES = {
    {id="white", tileset="fixtures_doors_01", base=0, label="White", prefix="ct_white_door_test_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_01_0","fixtures_doors_01_1","fixtures_doors_01_2","fixtures_doors_01_3"}},
    {id="brown", tileset="fixtures_doors_01", base=4, label="Brown paneled", prefix="ct_brown_door_test_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_01_4","fixtures_doors_01_5","fixtures_doors_01_6","fixtures_doors_01_7"}},
    {id="slats", tileset="fixtures_doors_01", base=8, label="Wooden slats", prefix="ct_slats_door_test_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_01_8","fixtures_doors_01_9","fixtures_doors_01_10","fixtures_doors_01_11"}},
    {id="red", tileset="fixtures_doors_01", base=12, label="Red paneled wood", prefix="ct_red_door_test_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_01_12","fixtures_doors_01_13","fixtures_doors_01_14","fixtures_doors_01_15"}},
    {id="beige", tileset="fixtures_doors_01", base=16, label="Beige glazed", prefix="ct_beige_door_test_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_01_16","fixtures_doors_01_17","fixtures_doors_01_18","fixtures_doors_01_19"}},
    {id="dark", tileset="fixtures_doors_01", base=20, label="Dark glazed", prefix="ct_dark_door_test_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_01_20","fixtures_doors_01_21","fixtures_doors_01_22","fixtures_doors_01_23"}},
    {id="new0", tileset="fixtures_doors_01", base=24, label="Industrial blue", prefix="ct_dv04_0_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_01_24","fixtures_doors_01_25","fixtures_doors_01_26","fixtures_doors_01_27"}},
    {id="new1", tileset="fixtures_doors_01", base=28, label="Rustic wood", prefix="ct_dv04_1_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_01_28","fixtures_doors_01_29","fixtures_doors_01_30","fixtures_doors_01_31"}},
    {id="new2", tileset="fixtures_doors_01", base=32, label="Glazed with keypad", prefix="ct_dv04_2_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_01_32","fixtures_doors_01_33","fixtures_doors_01_34","fixtures_doors_01_35"}},
    {id="new3", tileset="fixtures_doors_01", base=36, label="Large glass pane, red frame", prefix="ct_dv04_3_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_01_36","fixtures_doors_01_37","fixtures_doors_01_38","fixtures_doors_01_39"}},
    {id="new4", tileset="fixtures_doors_01", base=40, label="Large glass pane, dark frame", prefix="ct_dv04_4_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_01_40","fixtures_doors_01_41","fixtures_doors_01_42","fixtures_doors_01_43"}},
    {id="new5", tileset="fixtures_doors_01", base=44, label="White with four panes", prefix="ct_dv04_5_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_01_44","fixtures_doors_01_45","fixtures_doors_01_46","fixtures_doors_01_47"}},
    {id="new6", tileset="fixtures_doors_01", base=48, label="Glazed with long handle", prefix="ct_dv04_6_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_01_48","fixtures_doors_01_49","fixtures_doors_01_50","fixtures_doors_01_51"}},
    {id="new7", tileset="fixtures_doors_01", base=52, label="Solid gray", prefix="ct_dv04_7_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_01_52","fixtures_doors_01_53","fixtures_doors_01_54","fixtures_doors_01_55"}},
    {id="new8", tileset="fixtures_doors_01", base=56, label="Solid cream", prefix="ct_dv04_8_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_01_56","fixtures_doors_01_57","fixtures_doors_01_58","fixtures_doors_01_59"}},
    {id="new9", tileset="fixtures_doors_01", base=60, label="Industrial with porthole", prefix="ct_dv04_9_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_01_60","fixtures_doors_01_61","fixtures_doors_01_62","fixtures_doors_01_63"}},
    {id="new10", tileset="fixtures_doors_01", base=64, label="Solid yellow", prefix="ct_dv04_10_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_01_64","fixtures_doors_01_65","fixtures_doors_01_66","fixtures_doors_01_67"}},
    {id="new11", tileset="fixtures_doors_01", base=68, label="Worn wood", prefix="ct_dv04_11_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_01_68","fixtures_doors_01_69","fixtures_doors_01_70","fixtures_doors_01_71"}},
    {id="new12", tileset="carpentry_01", base=52, label="Carpentry wood 2", prefix="ct_dv04_12_", stride=4, offset=0, garage=false, overlay=false, sources={"carpentry_01_52","carpentry_01_53","carpentry_01_54","carpentry_01_55"}},
    {id="new13", tileset="carpentry_01", base=56, label="Carpentry wood 3", prefix="ct_dv04_13_", stride=4, offset=0, garage=false, overlay=false, sources={"carpentry_01_56","carpentry_01_57","carpentry_01_58","carpentry_01_59"}},
    {id="new14", tileset="fixtures_bathroom_02", base=16, label="Blue bathroom", prefix="ct_dv04_14_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_bathroom_02_16","fixtures_bathroom_02_17","fixtures_bathroom_02_18","fixtures_bathroom_02_19"}},
    {id="new15", tileset="fixtures_bathroom_02", base=32, label="Crescent outhouse", prefix="ct_dv04_15_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_bathroom_02_32","fixtures_bathroom_02_33","fixtures_bathroom_02_34","fixtures_bathroom_02_35"}},
    {id="new16", tileset="fixtures_doors_02", base=0, label="Blue paneled", prefix="ct_dv04_16_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_02_0","fixtures_doors_02_1","fixtures_doors_02_2","fixtures_doors_02_3"}},
    {id="new17", tileset="fixtures_doors_02", base=4, label="Brown with four panes", prefix="ct_dv04_17_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_02_4","fixtures_doors_02_5","fixtures_doors_02_6","fixtures_doors_02_7"}},
    {id="new18", tileset="fixtures_doors_02", base=8, label="Industrial red", prefix="ct_dv04_18_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_02_8","fixtures_doors_02_9","fixtures_doors_02_10","fixtures_doors_02_11"}},
    {id="new19", tileset="fixtures_doors_02", base=12, label="Industrial black", prefix="ct_dv04_19_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_02_12","fixtures_doors_02_13","fixtures_doors_02_14","fixtures_doors_02_15"}},
    {id="new20", tileset="location_community_police_01", base=4, label="Cell door", prefix="ct_dv04_20_", stride=4, offset=0, garage=false, overlay=false, sources={"location_community_police_01_4","location_community_police_01_5","location_community_police_01_6","location_community_police_01_7"}},
    {id="new21", tileset="location_restaurant_pileocrepe_01", base=48, label="Blue Pileocrepe", prefix="ct_dv04_21_", stride=4, offset=0, garage=false, overlay=false, sources={"location_restaurant_pileocrepe_01_48","location_restaurant_pileocrepe_01_49","location_restaurant_pileocrepe_01_50","location_restaurant_pileocrepe_01_51"}},
    {id="new22", tileset="location_restaurant_pileocrepe_01", base=52, label="Orange Pileocrepe", prefix="ct_dv04_22_", stride=4, offset=0, garage=false, overlay=false, sources={"location_restaurant_pileocrepe_01_52","location_restaurant_pileocrepe_01_53","location_restaurant_pileocrepe_01_54","location_restaurant_pileocrepe_01_55"}},
    {id="new23", tileset="location_restaurant_pizzawhirled_01", base=56, label="Glazed Pizza Whirled", prefix="ct_dv04_23_", stride=4, offset=0, garage=false, overlay=false, sources={"location_restaurant_pizzawhirled_01_56","location_restaurant_pizzawhirled_01_57","location_restaurant_pizzawhirled_01_58","location_restaurant_pizzawhirled_01_59"}},
    {id="new24", tileset="location_restaurant_pizzawhirled_01", base=60, label="Green Pizza Whirled", prefix="ct_dv04_24_", stride=4, offset=0, garage=false, overlay=false, sources={"location_restaurant_pizzawhirled_01_60","location_restaurant_pizzawhirled_01_61","location_restaurant_pizzawhirled_01_62","location_restaurant_pizzawhirled_01_63"}},
    {id="new25", tileset="location_restaurant_seahorse_01", base=48, label="Glazed Seahorse", prefix="ct_dv04_25_", stride=4, offset=0, garage=false, overlay=false, sources={"location_restaurant_seahorse_01_48","location_restaurant_seahorse_01_49","location_restaurant_seahorse_01_50","location_restaurant_seahorse_01_51"}},
    {id="new26", tileset="location_restaurant_spiffos_01", base=48, label="Glazed Spiffos", prefix="ct_dv04_26_", stride=4, offset=0, garage=false, overlay=false, sources={"location_restaurant_spiffos_01_48","location_restaurant_spiffos_01_49","location_restaurant_spiffos_01_50","location_restaurant_spiffos_01_51"}},
    {id="new27", tileset="location_restaurant_spiffos_01", base=52, label="Solid Spiffos", prefix="ct_dv04_27_", stride=4, offset=0, garage=false, overlay=false, sources={"location_restaurant_spiffos_01_52","location_restaurant_spiffos_01_53","location_restaurant_spiffos_01_54","location_restaurant_spiffos_01_55"}},
    {id="new28", tileset="location_shop_fossoil_01", base=60, label="Glazed Fossoil", prefix="ct_dv04_28_", stride=4, offset=0, garage=false, overlay=false, sources={"location_shop_fossoil_01_60","location_shop_fossoil_01_61","location_shop_fossoil_01_62","location_shop_fossoil_01_63"}},
    {id="new29", tileset="location_shop_gas2go_01", base=60, label="Glazed Gas2Go", prefix="ct_dv04_29_", stride=4, offset=0, garage=false, overlay=false, sources={"location_shop_gas2go_01_60","location_shop_gas2go_01_61","location_shop_gas2go_01_62","location_shop_gas2go_01_63"}},
    {id="new30", tileset="fixtures_doors_02", base=40, label="Glazed right-hand leaf", prefix="ct_dv04_pair_", stride=8, offset=0, garage=false, overlay=false, sources={"fixtures_doors_02_40","fixtures_doors_02_41","fixtures_doors_02_42","fixtures_doors_02_43"}},
    {id="new31", tileset="fixtures_doors_02", base=44, label="Glazed left-hand leaf", prefix="ct_dv04_pair_", stride=8, offset=4, garage=false, overlay=false, sources={"fixtures_doors_02_44","fixtures_doors_02_45","fixtures_doors_02_46","fixtures_doors_02_47"}},
    {id="carpentry_01_48", tileset="carpentry_01", base=48, label="carpentry_01_48", prefix="ct_v05_carpentry_01_48_", stride=4, offset=0, garage=false, overlay=false, sources={"carpentry_01_48","carpentry_01_49","carpentry_01_50","carpentry_01_51"}},
    {id="fixtures_bathroom_01_48", tileset="fixtures_bathroom_01", base=48, label="fixtures_bathroom_01_48", prefix="ct_v05_fixtures_bathroom_01_48_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_bathroom_01_48","fixtures_bathroom_01_49","fixtures_bathroom_01_50","fixtures_bathroom_01_51"}},
    {id="fixtures_bathroom_01_64", tileset="fixtures_bathroom_01", base=64, label="fixtures_bathroom_01_64", prefix="ct_v05_fixtures_bathroom_01_64_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_bathroom_01_64","fixtures_bathroom_01_65","fixtures_bathroom_01_66","fixtures_bathroom_01_67"}},
    {id="fixtures_doors_01_108", tileset="fixtures_doors_01", base=108, label="fixtures_doors_01_108", prefix="ct_v05_fixtures_doors_01_108_", stride=4, offset=0, garage=false, overlay=true, sources={"fixtures_doors_01_108","fixtures_doors_01_109","fixtures_doors_01_110","fixtures_doors_01_111"}},
    {id="fixtures_doors_01_116", tileset="fixtures_doors_01", base=116, label="fixtures_doors_01_116", prefix="ct_v05_fixtures_doors_01_116_", stride=4, offset=0, garage=false, overlay=true, sources={"fixtures_doors_01_116","fixtures_doors_01_117","fixtures_doors_01_118","fixtures_doors_01_119"}},
    {id="fixtures_doors_02_16", tileset="fixtures_doors_02", base=16, label="fixtures_doors_02_16", prefix="ct_v05_fixtures_doors_02_16_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_02_16","fixtures_doors_02_17","fixtures_doors_02_18","fixtures_doors_02_19"}},
    {id="fixtures_doors_02_20", tileset="fixtures_doors_02", base=20, label="fixtures_doors_02_20", prefix="ct_v05_fixtures_doors_02_20_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_02_20","fixtures_doors_02_21","fixtures_doors_02_22","fixtures_doors_02_23"}},
    {id="fixtures_doors_02_24", tileset="fixtures_doors_02", base=24, label="fixtures_doors_02_24", prefix="ct_v05_fixtures_doors_02_24_", stride=4, offset=0, garage=false, overlay=false, sources={"fixtures_doors_02_24","fixtures_doors_02_25","fixtures_doors_02_26","fixtures_doors_02_27"}},
    {id="fixtures_doors_02_48", tileset="fixtures_doors_02", base=48, label="fixtures_doors_02_48", prefix="ct_v05_fixtures_doors_02_48_", stride=8, offset=0, garage=false, overlay=false, sources={"fixtures_doors_02_48","fixtures_doors_02_49","fixtures_doors_02_50","fixtures_doors_02_51"}},
    {id="fixtures_doors_02_52", tileset="fixtures_doors_02", base=52, label="fixtures_doors_02_52", prefix="ct_v05_fixtures_doors_02_48_", stride=8, offset=4, garage=false, overlay=false, sources={"fixtures_doors_02_52","fixtures_doors_02_53","fixtures_doors_02_54","fixtures_doors_02_55"}},
    {id="fixtures_doors_02_56", tileset="fixtures_doors_02", base=56, label="fixtures_doors_02_56", prefix="ct_v05_fixtures_doors_02_56_", stride=8, offset=0, garage=false, overlay=false, sources={"fixtures_doors_02_56","fixtures_doors_02_57","fixtures_doors_02_58","fixtures_doors_02_59"}},
    {id="fixtures_doors_02_60", tileset="fixtures_doors_02", base=60, label="fixtures_doors_02_60", prefix="ct_v05_fixtures_doors_02_56_", stride=8, offset=4, garage=false, overlay=false, sources={"fixtures_doors_02_60","fixtures_doors_02_61","fixtures_doors_02_62","fixtures_doors_02_63"}},
    {id="location_community_church_small_01_24", tileset="location_community_church_small_01", base=24, label="location_community_church_small_01_24", prefix="ct_v05_location_community_church_small_01_24_", stride=8, offset=0, garage=false, overlay=false, sources={"location_community_church_small_01_24","location_community_church_small_01_25","location_community_church_small_01_26","location_community_church_small_01_27"}},
    {id="location_community_church_small_01_28", tileset="location_community_church_small_01", base=28, label="location_community_church_small_01_28", prefix="ct_v05_location_community_church_small_01_24_", stride=8, offset=4, garage=false, overlay=false, sources={"location_community_church_small_01_28","location_community_church_small_01_29","location_community_church_small_01_30","location_community_church_small_01_31"}},
    {id="location_community_church_small_01_64", tileset="location_community_church_small_01", base=64, label="location_community_church_small_01_64", prefix="ct_v05_location_community_church_small_01_64_", stride=8, offset=0, garage=false, overlay=false, sources={"location_community_church_small_01_64","location_community_church_small_01_65","location_community_church_small_01_66","location_community_church_small_01_67"}},
    {id="location_community_church_small_01_68", tileset="location_community_church_small_01", base=68, label="location_community_church_small_01_68", prefix="ct_v05_location_community_church_small_01_64_", stride=8, offset=4, garage=false, overlay=false, sources={"location_community_church_small_01_68","location_community_church_small_01_69","location_community_church_small_01_70","location_community_church_small_01_71"}},
    {id="industry_trucks_01_32", tileset="industry_trucks_01", base=32, label="industry_trucks_01_32", prefix="ct_v05_industry_trucks_01_32_", stride=16, offset=0, garage=true, overlay=true, sources={"industry_trucks_01_32","industry_trucks_01_33","industry_trucks_01_34","industry_trucks_01_35","industry_trucks_01_36","industry_trucks_01_37","industry_trucks_01_40","industry_trucks_01_41","industry_trucks_01_42","industry_trucks_01_43","industry_trucks_01_44","industry_trucks_01_45"}},
    {id="walls_garage_01_0", tileset="walls_garage_01", base=0, label="walls_garage_01_0", prefix="ct_v05_walls_garage_01_0_", stride=16, offset=0, garage=true, overlay=true, sources={"walls_garage_01_0","walls_garage_01_1","walls_garage_01_2","walls_garage_01_3","walls_garage_01_4","walls_garage_01_5","walls_garage_01_8","walls_garage_01_9","walls_garage_01_10","walls_garage_01_11","walls_garage_01_12","walls_garage_01_13"}},
    {id="walls_garage_01_16", tileset="walls_garage_01", base=16, label="walls_garage_01_16", prefix="ct_v05_walls_garage_01_16_", stride=16, offset=0, garage=true, overlay=true, sources={"walls_garage_01_16","walls_garage_01_17","walls_garage_01_18","walls_garage_01_19","walls_garage_01_20","walls_garage_01_21","walls_garage_01_24","walls_garage_01_25","walls_garage_01_26","walls_garage_01_27","walls_garage_01_28","walls_garage_01_29"}},
    {id="walls_garage_01_48", tileset="walls_garage_01", base=48, label="walls_garage_01_48", prefix="ct_v05_walls_garage_01_48_", stride=16, offset=0, garage=true, overlay=true, sources={"walls_garage_01_48","walls_garage_01_49","walls_garage_01_50","walls_garage_01_51","walls_garage_01_52","walls_garage_01_53","walls_garage_01_56","walls_garage_01_57","walls_garage_01_58","walls_garage_01_59","walls_garage_01_60","walls_garage_01_61"}},
    {id="walls_garage_02_0", tileset="walls_garage_02", base=0, label="walls_garage_02_0", prefix="ct_v05_walls_garage_02_0_", stride=16, offset=0, garage=true, overlay=true, sources={"walls_garage_02_0","walls_garage_02_1","walls_garage_02_2","walls_garage_02_3","walls_garage_02_4","walls_garage_02_5","walls_garage_02_8","walls_garage_02_9","walls_garage_02_10","walls_garage_02_11","walls_garage_02_12","walls_garage_02_13"}},
    {id="walls_garage_02_32", tileset="walls_garage_02", base=32, label="walls_garage_02_32", prefix="ct_v05_walls_garage_02_32_", stride=16, offset=0, garage=true, overlay=true, sources={"walls_garage_02_32","walls_garage_02_33","walls_garage_02_34","walls_garage_02_35","walls_garage_02_36","walls_garage_02_37","walls_garage_02_40","walls_garage_02_41","walls_garage_02_42","walls_garage_02_43","walls_garage_02_44","walls_garage_02_45"}},
    {id="walls_garage_02_48", tileset="walls_garage_02", base=48, label="walls_garage_02_48", prefix="ct_v05_walls_garage_02_48_", stride=16, offset=0, garage=true, overlay=true, sources={"walls_garage_02_48","walls_garage_02_49","walls_garage_02_50","walls_garage_02_51","walls_garage_02_52","walls_garage_02_53","walls_garage_02_56","walls_garage_02_57","walls_garage_02_58","walls_garage_02_59","walls_garage_02_60","walls_garage_02_61"}},
}
D.MODEL_PREFIXES, D.MODEL_NAMES, D.TEXTURE_NAMES, D.SOURCES, D.SOURCE_FAMILY, D.FAMILY_BY_ID = {}, {}, {}, {}, {}, {}
for _,family in ipairs(D.FAMILIES) do
    D.MODEL_PREFIXES[#D.MODEL_PREFIXES+1]=family.prefix
    D.FAMILY_BY_ID[family.id]=family
    for _,source in ipairs(family.sources) do
        local index=tonumber(string.match(source,"_(%d+)$"))
        D.SOURCES[source]=index
        D.SOURCE_FAMILY[source]=family
        for stage=1,3 do
            local name=family.prefix..tostring((stage-1)*family.stride+family.offset+index-family.base)
            D.TEXTURE_NAMES[#D.TEXTURE_NAMES+1]=name
            if not family.overlay then D.MODEL_NAMES[#D.MODEL_NAMES+1]=name end
        end
    end
end
D.BATCHES={{id="all",label="Full catalogue - 61 models",columns=9,families={}},
 {id="doors",label="54 doors",columns=9,families={}},
 {id="garages",label="7 complete garages",columns=4,families={}}}
for _,f in ipairs(D.FAMILIES) do
    table.insert(D.BATCHES[1].families,f.id)
    table.insert(D.BATCHES[f.garage and 3 or 2].families,f.id)
end
D.BATCH_BY_ID={}
for _,b in ipairs(D.BATCHES) do D.BATCH_BY_ID[b.id]=b end

D.whiteHD = true
D.hdQuality = false
D.EXTRA_HD_FAMILIES = {brown=true,slats=true,red=true,beige=true,dark=true,new0=true,new1=true,new2=true,new3=true,new4=true,new5=true,new6=true,new7=true,new8=true,new9=true,new10=true,new11=true,new12=true,new13=true,new14=true,new15=true,new16=true,new17=true,new18=true,new19=true,new20=true,new21=true,new22=true,new23=true,new24=true,new25=true,new26=true,new27=true,new28=true,new29=true,new30=true,new31=true,carpentry_01_48=true,fixtures_bathroom_01_48=true,fixtures_bathroom_01_64=true,fixtures_doors_02_16=true,fixtures_doors_02_20=true,fixtures_doors_02_24=true,fixtures_doors_02_48=true,fixtures_doors_02_52=true,fixtures_doors_02_56=true,fixtures_doors_02_60=true,location_community_church_small_01_24=true,location_community_church_small_01_28=true,location_community_church_small_01_64=true,location_community_church_small_01_68=true,fixtures_doors_01_108=true,fixtures_doors_01_116=true}
D.HD_ATLAS_FAMILIES = {red=true,beige=true,dark=true,new0=true,new1=true,new2=true,new3=true,new4=true,new5=true,new6=true,new7=true,new8=true,new9=true,new10=true,new11=true,new12=true,new13=true,new14=true,new15=true,new16=true,new17=true,new18=true,new19=true,new20=true,new21=true,new22=true,new23=true,new24=true,new25=true,new26=true,new27=true,new28=true,new29=true,new30=true,new31=true,carpentry_01_48=true,fixtures_bathroom_01_48=true,fixtures_bathroom_01_64=true,fixtures_doors_02_16=true,fixtures_doors_02_20=true,fixtures_doors_02_24=true,fixtures_doors_02_48=true,fixtures_doors_02_52=true,fixtures_doors_02_56=true,fixtures_doors_02_60=true,location_community_church_small_01_24=true,location_community_church_small_01_28=true,location_community_church_small_01_64=true,location_community_church_small_01_68=true,fixtures_doors_01_108=true,fixtures_doors_01_116=true}
D.extraHDReady = {}
D.INTACT_HD_FAMILIES = {["white"]=true,["brown"]=true,["slats"]=true,["red"]=true,["beige"]=true,["dark"]=true,["new0"]=true,["new1"]=true,["new2"]=true,["new3"]=true,["new4"]=true,["new5"]=true,["new6"]=true,["new7"]=true,["new8"]=true,["new9"]=true,["new10"]=true,["new11"]=true,["new12"]=true,["new13"]=true,["new14"]=true,["new15"]=true,["new16"]=true,["new17"]=true,["new18"]=true,["new19"]=true,["new20"]=true,["new21"]=true,["new22"]=true,["new23"]=true,["new24"]=true,["new25"]=true,["new26"]=true,["new27"]=true,["new28"]=true,["new29"]=true,["new30"]=true,["new31"]=true,["carpentry_01_48"]=true,["fixtures_bathroom_01_48"]=true,["fixtures_bathroom_01_64"]=true,["fixtures_doors_01_108"]=true,["fixtures_doors_01_116"]=true,["fixtures_doors_02_16"]=true,["fixtures_doors_02_20"]=true,["fixtures_doors_02_24"]=true,["fixtures_doors_02_48"]=true,["fixtures_doors_02_52"]=true,["fixtures_doors_02_56"]=true,["fixtures_doors_02_60"]=true,["location_community_church_small_01_24"]=true,["location_community_church_small_01_28"]=true,["location_community_church_small_01_64"]=true,["location_community_church_small_01_68"]=true}
D.intactHDReady = {}
D.HD_MODEL_NAMES={}
D.MODEL_PREFIXES[#D.MODEL_PREFIXES+1]="ct_hd_white_"
for i=0,11 do D.HD_MODEL_NAMES[#D.HD_MODEL_NAMES+1]="ct_hd_white_"..i end
for id in pairs(D.EXTRA_HD_FAMILIES) do D.MODEL_PREFIXES[#D.MODEL_PREFIXES+1]="ct_hd_"..id.."_" end

function D.log(message)
    print("[DDV01] " .. tostring(message))
end

function D.sourceName(door)
    local sprite = door and door:getSprite()
    return sprite and sprite:getName() or nil
end

function D.isSupported(door)
    local source=D.sourceName(door)
    local family=source and D.SOURCE_FAMILY[source] or nil
    return door ~= nil and instanceof(door, "IsoDoor")
        and family ~= nil and D.SOURCES[source] ~= nil
        and (IsoDoor.getGarageDoorIndex(door) == -1 or family.garage)
        and IsoDoor.getDoubleDoorIndex(door) == -1
end

function D.stageForHealth(health, maximum)
    if type(health) ~= "number" or type(maximum) ~= "number"
        or maximum <= 0 or health <= 0 then return 0 end
    local ratio = health / maximum
    if ratio > 0.75 then return 0 end
    if ratio >= 0.50 then return 1 end
    if ratio >= 0.25 then return 2 end
    return 3
end

local function individualStage(door)
    if door:isDestroyed() or door:getHealth() <= 0 then return 0 end
    local data = door:getModData()[D.DATA_KEY]
    local forced = type(data) == "table" and data.force or nil
    if type(forced) == "number" and forced >= 0 and forced <= 3
        and forced == math.floor(forced) then return forced end
    return D.stageForHealth(door:getHealth(), door:getMaxHealth())
end

function D.stage(door)
    local stage=individualStage(door)
    local family=D.SOURCE_FAMILY[D.sourceName(door)]
    if not family or not family.garage or door:isDestroyed() then return stage end
    local seen={[door]=true}
    for _,step in ipairs({IsoDoor.getGarageDoorPrev,IsoDoor.getGarageDoorNext}) do
        local current=door
        for i=1,32 do
            current=step(current)
            if not current or seen[current] or not D.isSupported(current)
                or current:isDestroyed() or current:getNorth()~=door:getNorth()
                or D.SOURCE_FAMILY[D.sourceName(current)]~=family then break end
            seen[current]=true
            stage=math.max(stage,individualStage(current))
        end
    end
    return stage
end

function D.modelName(door, stage)
    local view = (door:getNorth() and 1 or 0) + (door:isOpen() and 2 or 0)
    local source = D.SOURCES[D.sourceName(door)]
    if source == nil then return nil end
    local family = D.SOURCE_FAMILY[D.sourceName(door)]
    if stage == 0 then
        if D.hdQuality and D.intactHDReady[family.id] then
            return "ct_hd_"..family.id.."_"..tostring(12+view)
        end
        return nil
    end
    if family.id=="white" and D.whiteHD then
        return "ct_hd_white_"..tostring((stage-1)*4+view)
    end
    if D.hdQuality and D.extraHDReady[family.id] then
        return "ct_hd_"..family.id.."_"..tostring((stage-1)*4+view)
    end
    if family.overlay then
        view = source - family.base
        if not family.garage and D.hdQuality and D.hd2DReady and D.hd2DReady[family.id] then
            return "ct_hd2d_"..family.id.."_"..tostring((stage-1)*family.stride+view)
        end
    end
    return family.prefix .. tostring((stage - 1) * family.stride + family.offset + view)
end

function D.modelID(model)
    if not model then return nil end
    local id = model:getScriptObjectName()
    if id and string.sub(id, 1, 5) == "Base." then id = string.sub(id, 6) end
    return id
end

-- Native tile models can be anonymous copies, unlike registered script models.
-- Compare the full native rendering definition; never accept an arbitrary nil ID.
local function sameVector(a,b)
    -- Scalar accessors are exposed to Lua by B42 (also used by its editor).
    -- Avoid Java equals overload resolution on anonymous native model copies.
    return a:x()==b:x() and a:y()==b:y() and a:z()==b:z()
end

D.NATIVE_RUNTIME = {
    ["fixtures_doors_01_0"]="standard_door w closed",
    ["fixtures_doors_01_1"]="standard_door n closed",
    ["fixtures_doors_01_2"]="standard_door w open",
    ["fixtures_doors_01_3"]="standard_door n open",
    ["fixtures_doors_01_4"]="standard_door w closed",
    ["fixtures_doors_01_5"]="standard_door n closed",
    ["fixtures_doors_01_6"]="standard_door w open",
    ["fixtures_doors_01_7"]="standard_door n open",
    ["fixtures_doors_01_8"]="standard_door w closed",
    ["fixtures_doors_01_9"]="standard_door n closed",
    ["fixtures_doors_01_10"]="standard_door w open",
    ["fixtures_doors_01_11"]="standard_door n open",
    ["fixtures_doors_01_12"]="standard_door w closed",
    ["fixtures_doors_01_13"]="standard_door n closed",
    ["fixtures_doors_01_14"]="standard_door w open",
    ["fixtures_doors_01_15"]="standard_door n open",
    ["fixtures_doors_01_16"]="standard_door w closed",
    ["fixtures_doors_01_17"]="standard_door n closed",
    ["fixtures_doors_01_18"]="standard_door w open",
    ["fixtures_doors_01_19"]="standard_door n open",
    ["fixtures_doors_01_20"]="standard_door w closed",
    ["fixtures_doors_01_21"]="standard_door n closed",
    ["fixtures_doors_01_22"]="standard_door w open",
    ["fixtures_doors_01_23"]="standard_door n open",
    ["fixtures_doors_01_24"]="standard_door w closed",
    ["fixtures_doors_01_25"]="standard_door n closed",
    ["fixtures_doors_01_26"]="standard_door w open",
    ["fixtures_doors_01_27"]="standard_door n open",
    ["fixtures_doors_01_28"]="standard_door w closed",
    ["fixtures_doors_01_29"]="standard_door n closed",
    ["fixtures_doors_01_30"]="standard_door w open",
    ["fixtures_doors_01_31"]="standard_door n open",
    ["fixtures_doors_01_32"]="standard_door w closed",
    ["fixtures_doors_01_33"]="standard_door n closed",
    ["fixtures_doors_01_34"]="standard_door w open",
    ["fixtures_doors_01_35"]="standard_door n open",
    ["fixtures_doors_01_36"]="standard_door w closed",
    ["fixtures_doors_01_37"]="standard_door n closed",
    ["fixtures_doors_01_38"]="standard_door w open",
    ["fixtures_doors_01_39"]="standard_door n open",
    ["fixtures_doors_01_40"]="standard_door w closed",
    ["fixtures_doors_01_41"]="standard_door n closed",
    ["fixtures_doors_01_42"]="standard_door w open",
    ["fixtures_doors_01_43"]="standard_door n open",
    ["fixtures_doors_01_44"]="standard_door w closed",
    ["fixtures_doors_01_45"]="standard_door n closed",
    ["fixtures_doors_01_46"]="standard_door w open",
    ["fixtures_doors_01_47"]="standard_door n open",
    ["fixtures_doors_01_48"]="standard_door w closed",
    ["fixtures_doors_01_49"]="standard_door n closed",
    ["fixtures_doors_01_50"]="standard_door w open",
    ["fixtures_doors_01_51"]="standard_door n open",
    ["fixtures_doors_01_52"]="standard_door w closed",
    ["fixtures_doors_01_53"]="standard_door n closed",
    ["fixtures_doors_01_54"]="standard_door w open",
    ["fixtures_doors_01_55"]="standard_door n open",
    ["fixtures_doors_01_56"]="standard_door w closed",
    ["fixtures_doors_01_57"]="standard_door n closed",
    ["fixtures_doors_01_58"]="standard_door w open",
    ["fixtures_doors_01_59"]="standard_door n open",
    ["fixtures_doors_01_60"]="standard_door w closed",
    ["fixtures_doors_01_61"]="standard_door n closed",
    ["fixtures_doors_01_62"]="standard_door w open",
    ["fixtures_doors_01_63"]="standard_door n open",
    ["fixtures_doors_01_64"]="standard_door w closed",
    ["fixtures_doors_01_65"]="standard_door n closed",
    ["fixtures_doors_01_66"]="standard_door w open",
    ["fixtures_doors_01_67"]="standard_door n open",
    ["fixtures_doors_01_68"]="standard_door w closed",
    ["fixtures_doors_01_69"]="standard_door n closed",
    ["fixtures_doors_01_70"]="standard_door w open",
    ["fixtures_doors_01_71"]="standard_door n open",
    ["fixtures_doors_02_0"]="standard_door w closed",
    ["fixtures_doors_02_1"]="standard_door n closed",
    ["fixtures_doors_02_2"]="standard_door w open",
    ["fixtures_doors_02_3"]="standard_door n open",
    ["fixtures_doors_02_4"]="standard_door w closed",
    ["fixtures_doors_02_5"]="standard_door n closed",
    ["fixtures_doors_02_6"]="standard_door w open",
    ["fixtures_doors_02_7"]="standard_door n open",
    ["fixtures_doors_02_8"]="standard_door w closed",
    ["fixtures_doors_02_9"]="standard_door n closed",
    ["fixtures_doors_02_10"]="standard_door w open",
    ["fixtures_doors_02_11"]="standard_door n open",
    ["fixtures_doors_02_12"]="standard_door w closed",
    ["fixtures_doors_02_13"]="standard_door n closed",
    ["fixtures_doors_02_14"]="standard_door w open",
    ["fixtures_doors_02_15"]="standard_door n open",
    ["fixtures_doors_02_40"]="pair_door right w closed",
    ["fixtures_doors_02_41"]="pair_door left n closed",
    ["fixtures_doors_02_42"]="pair_door right w open",
    ["fixtures_doors_02_43"]="pair_door left n open",
    ["fixtures_doors_02_44"]="pair_door left w closed",
    ["fixtures_doors_02_45"]="pair_door right n closed",
    ["fixtures_doors_02_46"]="pair_door left w open",
    ["fixtures_doors_02_47"]="pair_door right n open",
    ["fixtures_doors_02_48"]="pair_door right w closed",
    ["fixtures_doors_02_49"]="pair_door left n closed",
    ["fixtures_doors_02_50"]="pair_door right w open",
    ["fixtures_doors_02_51"]="pair_door left n open",
    ["fixtures_doors_02_52"]="pair_door left w closed",
    ["fixtures_doors_02_53"]="pair_door right n closed",
    ["fixtures_doors_02_54"]="pair_door left w open",
    ["fixtures_doors_02_55"]="pair_door right n open",
    ["fixtures_doors_02_56"]="pair_door right w closed",
    ["fixtures_doors_02_57"]="pair_door left n closed",
    ["fixtures_doors_02_58"]="pair_door right w open",
    ["fixtures_doors_02_59"]="pair_door left n open",
    ["fixtures_doors_02_60"]="pair_door left w closed",
    ["fixtures_doors_02_61"]="pair_door right n closed",
    ["fixtures_doors_02_62"]="pair_door left w open",
    ["fixtures_doors_02_63"]="pair_door right n open",
    ["location_community_church_small_01_24"]="pair_door right w closed",
    ["location_community_church_small_01_25"]="pair_door left n closed",
    ["location_community_church_small_01_26"]="pair_door right w open",
    ["location_community_church_small_01_27"]="pair_door left n open",
    ["location_community_church_small_01_28"]="pair_door left w closed",
    ["location_community_church_small_01_29"]="pair_door right n closed",
    ["location_community_church_small_01_30"]="pair_door left w open",
    ["location_community_church_small_01_31"]="pair_door right n open",
    ["location_community_church_small_01_64"]="pair_door right w closed",
    ["location_community_church_small_01_65"]="pair_door left n closed",
    ["location_community_church_small_01_66"]="pair_door right w open",
    ["location_community_church_small_01_67"]="pair_door left n open",
    ["location_community_church_small_01_68"]="pair_door left w closed",
    ["location_community_church_small_01_69"]="pair_door right n closed",
    ["location_community_church_small_01_70"]="pair_door left w open",
    ["location_community_church_small_01_71"]="pair_door right n open",
    ["location_community_police_01_4"]="standard_door w closed",
    ["location_community_police_01_5"]="standard_door n closed",
    ["location_community_police_01_6"]="standard_door w open",
    ["location_community_police_01_7"]="standard_door n open",
    ["carpentry_01_52"]="standard_door w closed",
    ["carpentry_01_53"]="standard_door n closed",
    ["carpentry_01_54"]="standard_door w open",
    ["carpentry_01_55"]="standard_door n open",
    ["carpentry_01_56"]="standard_door w closed",
    ["carpentry_01_57"]="standard_door n closed",
    ["carpentry_01_58"]="standard_door w open",
    ["carpentry_01_59"]="standard_door n open",
    ["fixtures_bathroom_02_16"]="standard_door w closed",
    ["fixtures_bathroom_02_17"]="standard_door n closed",
    ["fixtures_bathroom_02_18"]="standard_door w open",
    ["fixtures_bathroom_02_19"]="standard_door n open",
    ["fixtures_bathroom_02_32"]="standard_door w closed",
    ["fixtures_bathroom_02_33"]="standard_door n closed",
    ["fixtures_bathroom_02_34"]="standard_door w open",
    ["fixtures_bathroom_02_35"]="standard_door n open",
    ["location_shop_fossoil_01_60"]="standard_door w closed",
    ["location_shop_fossoil_01_61"]="standard_door n closed",
    ["location_shop_fossoil_01_62"]="standard_door w open",
    ["location_shop_fossoil_01_63"]="standard_door n open",
    ["location_restaurant_spiffos_01_48"]="standard_door w closed",
    ["location_restaurant_spiffos_01_49"]="standard_door n closed",
    ["location_restaurant_spiffos_01_50"]="standard_door w open",
    ["location_restaurant_spiffos_01_51"]="standard_door n open",
    ["location_restaurant_spiffos_01_52"]="standard_door w closed",
    ["location_restaurant_spiffos_01_53"]="standard_door n closed",
    ["location_restaurant_spiffos_01_54"]="standard_door w open",
    ["location_restaurant_spiffos_01_55"]="standard_door n open",
    ["location_restaurant_seahorse_01_48"]="standard_door w closed",
    ["location_restaurant_seahorse_01_49"]="standard_door n closed",
    ["location_restaurant_seahorse_01_50"]="standard_door w open",
    ["location_restaurant_seahorse_01_51"]="standard_door n open",
    ["location_restaurant_pizzawhirled_01_56"]="standard_door w closed",
    ["location_restaurant_pizzawhirled_01_57"]="standard_door n closed",
    ["location_restaurant_pizzawhirled_01_58"]="standard_door w open",
    ["location_restaurant_pizzawhirled_01_59"]="standard_door n open",
    ["location_restaurant_pizzawhirled_01_60"]="standard_door w closed",
    ["location_restaurant_pizzawhirled_01_61"]="standard_door n closed",
    ["location_restaurant_pizzawhirled_01_62"]="standard_door w open",
    ["location_restaurant_pizzawhirled_01_63"]="standard_door n open",
    ["location_restaurant_pileocrepe_01_48"]="standard_door w closed",
    ["location_restaurant_pileocrepe_01_49"]="standard_door n closed",
    ["location_restaurant_pileocrepe_01_50"]="standard_door w open",
    ["location_restaurant_pileocrepe_01_51"]="standard_door n open",
    ["location_restaurant_pileocrepe_01_52"]="standard_door w closed",
    ["location_restaurant_pileocrepe_01_53"]="standard_door n closed",
    ["location_restaurant_pileocrepe_01_54"]="standard_door w open",
    ["location_restaurant_pileocrepe_01_55"]="standard_door n open",
    ["location_shop_gas2go_01_60"]="standard_door w closed",
    ["location_shop_gas2go_01_61"]="standard_door n closed",
    ["location_shop_gas2go_01_62"]="standard_door w open",
    ["location_shop_gas2go_01_63"]="standard_door n open",
}

function D.isNativeModel(model, source)
    if not model then return true end
    local id=D.modelID(model)
    if id then return id==source end
    local native=ScriptManager.instance:getSpriteModel(source)
    if not native then return false end
    if model==native then return true end
    local ok,same=pcall(function()
        local sameScript=model:getModelScriptName()==native:getModelScriptName()
        if not sameScript and model:getTextureName()==nil and native:getTextureName()==nil then
            -- ViewpointDoor PairedDoors.choose swaps only the mesh script;
            -- it retains the native runtime, pose and transforms verbatim.
            local runtime=native:getRuntimeString() or D.NATIVE_RUNTIME[source]
            local shift=runtime=="pair_door left w closed" and 2
                or runtime=="pair_door right n open" and -2 or nil
            if shift and model:getRuntimeString()==runtime then
                local stem,index=string.match(source,"^(.*_)(%d+)$")
                local other=stem and ScriptManager.instance:getSpriteModel(stem..tostring(tonumber(index)+shift))
                sameScript=other~=nil and model:getModelScriptName()==other:getModelScriptName()
            end
        end
        return sameScript
            and model:getTextureName()==native:getTextureName()
            and model:getScale()==native:getScale()
            and model:getAnimationName()==native:getAnimationName()
            and model:getAnimationTime()==native:getAnimationTime()
            and sameVector(model:getTranslate(),native:getTranslate())
            and sameVector(model:getRotate(),native:getRotate())
    end)
    return ok and same==true
end

function D.isOurModel(model)
    local id = D.modelID(model)
    if not id then return false end
    for _, prefix in ipairs(D.MODEL_PREFIXES) do
        if string.sub(id, 1, #prefix) == prefix then return true end
    end
    return false
end

function D.snapshot(door)
    local square = door:getSquare()
    return {
        health = door:getHealth(), maximum = door:getMaxHealth(),
        open = door:isOpen(), north = door:getNorth(),
        locked = door:isLocked(), lockedByKey = door:isLockedByKey(),
        keyId = door:getKeyId(), sprite = D.sourceName(door),
        index = door:getObjectIndex(), square = square,
        barricaded = door:isBarricaded(), destroyed = door:isDestroyed(),
    }
end

function D.sameState(before, after)
    for key, value in pairs(before) do
        if after[key] ~= value then return false, key end
    end
    return true
end

function D.canTest(player)
    if not player then return false end
    if not isClient() and not isServer() then return true end
    return string.lower(tostring(player:getAccessLevel())) == "admin"
end

function D.near(player, square, radius)
    return player ~= nil and square ~= nil
        and math.floor(player:getZ()) == square:getZ()
        and math.abs(player:getX() - square:getX()) <= radius
        and math.abs(player:getY() - square:getY()) <= radius
end

return D
