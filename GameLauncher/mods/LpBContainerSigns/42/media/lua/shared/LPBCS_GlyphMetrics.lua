--[[
    © 2026 Warlord-Fox3. Tous droits réservés / All Rights Reserved.

    Toute réutilisation, modification, redistribution ou inclusion dans un
    modpack sans autorisation écrite préalable est strictement interdite.

    Any reuse, modification, redistribution, or inclusion in a modpack
    without prior written permission is strictly prohibited.
]]

--[[
    LPBCS_GlyphMetrics -- GENERE PAR SCRIPT, ne pas editer a la main.

    Produit par tools/make_assets.py depuis zomboidLarge.fnt, l'atlas du jeu (Noto Sans
    SemiBold, SIL OFL). Tout est en pixels du cadre de tuile 2x.

      adv      de combien avancer apres ce caractere
      ox       decalage horizontal du glyphe
      e / s    le sprite et son decalage vertical, par face

    Une entree sans e ni s est un caractere sans image -- l'espace. Son avance
    compte quand meme : LPBCS_Sprites ne deplace son curseur que sur un glyphe
    connu, et sans cette entree les mots se collent les uns aux autres.

    FOLD dit quoi ecrire a la place d'un caractere que GLYPHS ne porte pas :
    la meme lettre sans son accent, en une ou deux lettres (219 entrees,
    de U+00A0 a U+024F). Ce qui n'y est pas non plus prend l'avance
    d'une espace -- LPBCS_Sprites.fold s'en charge. Un mot ne se referme jamais
    sur un caractere manquant : il perd un accent, pas une place.

    Capitale 7 px (echelle 0.350 de l'atlas source), ligne 12 px.
    PLANKS porte les fonds d'une ligne, PLANKS2 ceux de deux, et ainsi de suite :
    PLANKS2 en fait 31 px de haut, PLANKS3 en fait 43 px de haut.
]]

LPBCS = LPBCS or {}

LPBCS.GLYPH_LINE_HEIGHT = 12
LPBCS.GLYPH_SLOPE = 0.50
LPBCS.PLANK_HEIGHT = 20
LPBCS.PLANK_HEIGHT_2 = 31
LPBCS.PLANK_HEIGHT_3 = 43
LPBCS.PLANK_STEP = 4
LPBCS.PLANK_MIN = 16
LPBCS.PLANK_MAX = 88
LPBCS.MAX_LINES = 3

LPBCS.GLYPHS = {
    [32] = { adv =  2.00, ox =  0.00 },
    [33] = { adv =  2.00, ox =  0.00, e = { sprite = "LPBCS_g0033e", oy =   4.00 }, s = { sprite = "LPBCS_g0033s", oy =   4.00 } },
    [34] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0034e", oy =   3.00 }, s = { sprite = "LPBCS_g0034s", oy =   4.00 } },
    [35] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0035e", oy =   2.00 }, s = { sprite = "LPBCS_g0035s", oy =   4.00 } },
    [37] = { adv =  8.00, ox =  0.00, e = { sprite = "LPBCS_g0037e", oy =   1.00 }, s = { sprite = "LPBCS_g0037s", oy =   4.00 } },
    [38] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0038e", oy =   2.00 }, s = { sprite = "LPBCS_g0038s", oy =   4.00 } },
    [39] = { adv =  2.00, ox =  0.00, e = { sprite = "LPBCS_g0039e", oy =   4.00 }, s = { sprite = "LPBCS_g0039s", oy =   4.00 } },
    [40] = { adv =  2.00, ox =  0.00, e = { sprite = "LPBCS_g0040e", oy =   3.00 }, s = { sprite = "LPBCS_g0040s", oy =   4.00 } },
    [41] = { adv =  2.00, ox =  0.00, e = { sprite = "LPBCS_g0041e", oy =   3.00 }, s = { sprite = "LPBCS_g0041s", oy =   4.00 } },
    [42] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0042e", oy =   3.00 }, s = { sprite = "LPBCS_g0042s", oy =   4.00 } },
    [43] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0043e", oy =   4.00 }, s = { sprite = "LPBCS_g0043s", oy =   5.00 } },
    [45] = { adv =  2.00, ox =  0.00, e = { sprite = "LPBCS_g0045e", oy =   7.00 }, s = { sprite = "LPBCS_g0045s", oy =   8.00 } },
    [46] = { adv =  2.00, ox =  0.00, e = { sprite = "LPBCS_g0046e", oy =   9.00 }, s = { sprite = "LPBCS_g0046s", oy =   9.00 } },
    [47] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0047e", oy =   3.00 }, s = { sprite = "LPBCS_g0047s", oy =   5.00 } },
    [48] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0048e", oy =   2.00 }, s = { sprite = "LPBCS_g0048s", oy =   4.00 } },
    [49] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0049e", oy =   3.00 }, s = { sprite = "LPBCS_g0049s", oy =   4.00 } },
    [50] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0050e", oy =   2.00 }, s = { sprite = "LPBCS_g0050s", oy =   4.00 } },
    [51] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0051e", oy =   2.00 }, s = { sprite = "LPBCS_g0051s", oy =   4.00 } },
    [52] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0052e", oy =   2.00 }, s = { sprite = "LPBCS_g0052s", oy =   5.00 } },
    [53] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0053e", oy =   2.00 }, s = { sprite = "LPBCS_g0053s", oy =   4.00 } },
    [54] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0054e", oy =   2.00 }, s = { sprite = "LPBCS_g0054s", oy =   4.00 } },
    [55] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0055e", oy =   2.00 }, s = { sprite = "LPBCS_g0055s", oy =   4.00 } },
    [56] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0056e", oy =   2.00 }, s = { sprite = "LPBCS_g0056s", oy =   4.00 } },
    [57] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0057e", oy =   2.00 }, s = { sprite = "LPBCS_g0057s", oy =   4.00 } },
    [58] = { adv =  2.00, ox =  0.00, e = { sprite = "LPBCS_g0058e", oy =   5.00 }, s = { sprite = "LPBCS_g0058s", oy =   5.00 } },
    [59] = { adv =  2.00, ox =  0.00, e = { sprite = "LPBCS_g0059e", oy =   4.00 }, s = { sprite = "LPBCS_g0059s", oy =   5.00 } },
    [61] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0061e", oy =   4.00 }, s = { sprite = "LPBCS_g0061s", oy =   6.00 } },
    [63] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0063e", oy =   2.00 }, s = { sprite = "LPBCS_g0063s", oy =   4.00 } },
    [65] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0065e", oy =   2.00 }, s = { sprite = "LPBCS_g0065s", oy =   5.00 } },
    [66] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0066e", oy =   2.00 }, s = { sprite = "LPBCS_g0066s", oy =   4.00 } },
    [67] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0067e", oy =   2.00 }, s = { sprite = "LPBCS_g0067s", oy =   4.00 } },
    [68] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0068e", oy =   2.00 }, s = { sprite = "LPBCS_g0068s", oy =   4.00 } },
    [69] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0069e", oy =   2.00 }, s = { sprite = "LPBCS_g0069s", oy =   4.00 } },
    [70] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0070e", oy =   2.00 }, s = { sprite = "LPBCS_g0070s", oy =   4.00 } },
    [71] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0071e", oy =   2.00 }, s = { sprite = "LPBCS_g0071s", oy =   4.00 } },
    [72] = { adv =  8.00, ox =  0.00, e = { sprite = "LPBCS_g0072e", oy =   2.00 }, s = { sprite = "LPBCS_g0072s", oy =   4.00 } },
    [73] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0073e", oy =   3.00 }, s = { sprite = "LPBCS_g0073s", oy =   4.00 } },
    [74] = { adv =  2.00, ox =  0.00, e = { sprite = "LPBCS_g0074e", oy =   3.00 }, s = { sprite = "LPBCS_g0074s", oy =   4.00 } },
    [75] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0075e", oy =   2.00 }, s = { sprite = "LPBCS_g0075s", oy =   4.00 } },
    [76] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0076e", oy =   3.00 }, s = { sprite = "LPBCS_g0076s", oy =   4.00 } },
    [77] = { adv =  8.00, ox =  0.00, e = { sprite = "LPBCS_g0077e", oy =   1.00 }, s = { sprite = "LPBCS_g0077s", oy =   4.00 } },
    [78] = { adv =  8.00, ox =  0.00, e = { sprite = "LPBCS_g0078e", oy =   2.00 }, s = { sprite = "LPBCS_g0078s", oy =   4.00 } },
    [79] = { adv =  8.00, ox =  0.00, e = { sprite = "LPBCS_g0079e", oy =   1.00 }, s = { sprite = "LPBCS_g0079s", oy =   4.00 } },
    [80] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0080e", oy =   2.00 }, s = { sprite = "LPBCS_g0080s", oy =   4.00 } },
    [81] = { adv =  8.00, ox =  0.00, e = { sprite = "LPBCS_g0081e", oy =   1.00 }, s = { sprite = "LPBCS_g0081s", oy =   4.00 } },
    [82] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0082e", oy =   2.00 }, s = { sprite = "LPBCS_g0082s", oy =   4.00 } },
    [83] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0083e", oy =   2.00 }, s = { sprite = "LPBCS_g0083s", oy =   4.00 } },
    [84] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0084e", oy =   2.00 }, s = { sprite = "LPBCS_g0084s", oy =   4.00 } },
    [85] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0085e", oy =   2.00 }, s = { sprite = "LPBCS_g0085s", oy =   4.00 } },
    [86] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0086e", oy =   1.00 }, s = { sprite = "LPBCS_g0086s", oy =   4.00 } },
    [87] = { adv =  8.00, ox =  0.00, e = { sprite = "LPBCS_g0087e", oy =   0.00 }, s = { sprite = "LPBCS_g0087s", oy =   4.00 } },
    [88] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0088e", oy =   2.00 }, s = { sprite = "LPBCS_g0088s", oy =   4.00 } },
    [89] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0089e", oy =   2.00 }, s = { sprite = "LPBCS_g0089s", oy =   4.00 } },
    [90] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0090e", oy =   2.00 }, s = { sprite = "LPBCS_g0090s", oy =   4.00 } },
    [95] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0095e", oy =   9.00 }, s = { sprite = "LPBCS_g0095s", oy =  11.00 } },
    [97] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0097e", oy =   3.00 }, s = { sprite = "LPBCS_g0097s", oy =   5.00 } },
    [98] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0098e", oy =   3.00 }, s = { sprite = "LPBCS_g0098s", oy =   4.00 } },
    [99] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0099e", oy =   3.00 }, s = { sprite = "LPBCS_g0099s", oy =   5.00 } },
    [100] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0100e", oy =   2.00 }, s = { sprite = "LPBCS_g0100s", oy =   5.00 } },
    [101] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0101e", oy =   3.00 }, s = { sprite = "LPBCS_g0101s", oy =   5.00 } },
    [102] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0102e", oy =   2.00 }, s = { sprite = "LPBCS_g0102s", oy =   4.00 } },
    [103] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0103e", oy =   3.00 }, s = { sprite = "LPBCS_g0103s", oy =   5.00 } },
    [104] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0104e", oy =   3.00 }, s = { sprite = "LPBCS_g0104s", oy =   4.00 } },
    [105] = { adv =  2.00, ox =  0.00, e = { sprite = "LPBCS_g0105e", oy =   4.00 }, s = { sprite = "LPBCS_g0105s", oy =   4.00 } },
    [106] = { adv =  2.00, ox =  0.00, e = { sprite = "LPBCS_g0106e", oy =   3.00 }, s = { sprite = "LPBCS_g0106s", oy =   4.00 } },
    [107] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0107e", oy =   3.00 }, s = { sprite = "LPBCS_g0107s", oy =   4.00 } },
    [108] = { adv =  2.00, ox =  0.00, e = { sprite = "LPBCS_g0108e", oy =   4.00 }, s = { sprite = "LPBCS_g0108s", oy =   4.00 } },
    [109] = { adv =  8.00, ox =  0.00, e = { sprite = "LPBCS_g0109e", oy =   2.00 }, s = { sprite = "LPBCS_g0109s", oy =   5.00 } },
    [110] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0110e", oy =   3.00 }, s = { sprite = "LPBCS_g0110s", oy =   5.00 } },
    [111] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0111e", oy =   3.00 }, s = { sprite = "LPBCS_g0111s", oy =   5.00 } },
    [112] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0112e", oy =   3.00 }, s = { sprite = "LPBCS_g0112s", oy =   5.00 } },
    [113] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0113e", oy =   3.00 }, s = { sprite = "LPBCS_g0113s", oy =   5.00 } },
    [114] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0114e", oy =   4.00 }, s = { sprite = "LPBCS_g0114s", oy =   5.00 } },
    [115] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0115e", oy =   3.00 }, s = { sprite = "LPBCS_g0115s", oy =   5.00 } },
    [116] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0116e", oy =   5.00 }, s = { sprite = "LPBCS_g0116s", oy =   5.00 } },
    [117] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0117e", oy =   4.00 }, s = { sprite = "LPBCS_g0117s", oy =   6.00 } },
    [118] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0118e", oy =   4.00 }, s = { sprite = "LPBCS_g0118s", oy =   6.00 } },
    [119] = { adv =  8.00, ox =  0.00, e = { sprite = "LPBCS_g0119e", oy =   3.00 }, s = { sprite = "LPBCS_g0119s", oy =   6.00 } },
    [120] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0120e", oy =   4.00 }, s = { sprite = "LPBCS_g0120s", oy =   6.00 } },
    [121] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0121e", oy =   4.00 }, s = { sprite = "LPBCS_g0121s", oy =   6.00 } },
    [122] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0122e", oy =   4.00 }, s = { sprite = "LPBCS_g0122s", oy =   6.00 } },
    [161] = { adv =  2.00, ox =  0.00, e = { sprite = "LPBCS_g0161e", oy =   6.00 }, s = { sprite = "LPBCS_g0161s", oy =   6.00 } },
    [191] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0191e", oy =   5.00 }, s = { sprite = "LPBCS_g0191s", oy =   6.00 } },
    [192] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0192e", oy =   0.00 }, s = { sprite = "LPBCS_g0192s", oy =   2.00 } },
    [193] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0193e", oy =  -1.00 }, s = { sprite = "LPBCS_g0193s", oy =   3.00 } },
    [194] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0194e", oy =   0.00 }, s = { sprite = "LPBCS_g0194s", oy =   2.00 } },
    [195] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0195e", oy =  -1.00 }, s = { sprite = "LPBCS_g0195s", oy =   2.00 } },
    [196] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0196e", oy =   0.00 }, s = { sprite = "LPBCS_g0196s", oy =   2.00 } },
    [199] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0199e", oy =   2.00 }, s = { sprite = "LPBCS_g0199s", oy =   4.00 } },
    [200] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0200e", oy =   1.00 }, s = { sprite = "LPBCS_g0200s", oy =   2.00 } },
    [201] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0201e", oy =   0.00 }, s = { sprite = "LPBCS_g0201s", oy =   2.00 } },
    [202] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0202e", oy =   0.00 }, s = { sprite = "LPBCS_g0202s", oy =   2.00 } },
    [203] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0203e", oy =   0.00 }, s = { sprite = "LPBCS_g0203s", oy =   2.00 } },
    [204] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0204e", oy =   2.00 }, s = { sprite = "LPBCS_g0204s", oy =   2.00 } },
    [205] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0205e", oy =   1.00 }, s = { sprite = "LPBCS_g0205s", oy =   2.00 } },
    [206] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0206e", oy =   1.00 }, s = { sprite = "LPBCS_g0206s", oy =   2.00 } },
    [207] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0207e", oy =   1.00 }, s = { sprite = "LPBCS_g0207s", oy =   2.00 } },
    [209] = { adv =  8.00, ox =  0.00, e = { sprite = "LPBCS_g0209e", oy =   0.00 }, s = { sprite = "LPBCS_g0209s", oy =   2.00 } },
    [210] = { adv =  8.00, ox =  0.00, e = { sprite = "LPBCS_g0210e", oy =   0.00 }, s = { sprite = "LPBCS_g0210s", oy =   2.00 } },
    [211] = { adv =  8.00, ox =  0.00, e = { sprite = "LPBCS_g0211e", oy =  -1.00 }, s = { sprite = "LPBCS_g0211s", oy =   3.00 } },
    [212] = { adv =  8.00, ox =  0.00, e = { sprite = "LPBCS_g0212e", oy =   0.00 }, s = { sprite = "LPBCS_g0212s", oy =   2.00 } },
    [213] = { adv =  8.00, ox =  0.00, e = { sprite = "LPBCS_g0213e", oy =  -1.00 }, s = { sprite = "LPBCS_g0213s", oy =   2.00 } },
    [214] = { adv =  8.00, ox =  0.00, e = { sprite = "LPBCS_g0214e", oy =   0.00 }, s = { sprite = "LPBCS_g0214s", oy =   2.00 } },
    [217] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0217e", oy =   1.00 }, s = { sprite = "LPBCS_g0217s", oy =   2.00 } },
    [218] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0218e", oy =   0.00 }, s = { sprite = "LPBCS_g0218s", oy =   3.00 } },
    [219] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0219e", oy =   0.00 }, s = { sprite = "LPBCS_g0219s", oy =   2.00 } },
    [220] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0220e", oy =   0.00 }, s = { sprite = "LPBCS_g0220s", oy =   2.00 } },
    [223] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0223e", oy =   2.00 }, s = { sprite = "LPBCS_g0223s", oy =   4.00 } },
    [224] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0224e", oy =   3.00 }, s = { sprite = "LPBCS_g0224s", oy =   4.00 } },
    [225] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0225e", oy =   2.00 }, s = { sprite = "LPBCS_g0225s", oy =   5.00 } },
    [226] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0226e", oy =   2.00 }, s = { sprite = "LPBCS_g0226s", oy =   4.00 } },
    [227] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0227e", oy =   2.00 }, s = { sprite = "LPBCS_g0227s", oy =   4.00 } },
    [228] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0228e", oy =   2.00 }, s = { sprite = "LPBCS_g0228s", oy =   4.00 } },
    [231] = { adv =  4.00, ox =  0.00, e = { sprite = "LPBCS_g0231e", oy =   3.00 }, s = { sprite = "LPBCS_g0231s", oy =   5.00 } },
    [232] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0232e", oy =   3.00 }, s = { sprite = "LPBCS_g0232s", oy =   4.00 } },
    [233] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0233e", oy =   2.00 }, s = { sprite = "LPBCS_g0233s", oy =   5.00 } },
    [234] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0234e", oy =   2.00 }, s = { sprite = "LPBCS_g0234s", oy =   4.00 } },
    [235] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0235e", oy =   2.00 }, s = { sprite = "LPBCS_g0235s", oy =   4.00 } },
    [236] = { adv =  2.00, ox =  0.00, e = { sprite = "LPBCS_g0236e", oy =   3.00 }, s = { sprite = "LPBCS_g0236s", oy =   4.00 } },
    [237] = { adv =  2.00, ox =  0.00, e = { sprite = "LPBCS_g0237e", oy =   3.00 }, s = { sprite = "LPBCS_g0237s", oy =   4.00 } },
    [238] = { adv =  2.00, ox =  0.00, e = { sprite = "LPBCS_g0238e", oy =   2.00 }, s = { sprite = "LPBCS_g0238s", oy =   4.00 } },
    [239] = { adv =  2.00, ox =  0.00, e = { sprite = "LPBCS_g0239e", oy =   3.00 }, s = { sprite = "LPBCS_g0239s", oy =   4.00 } },
    [241] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0241e", oy =   2.00 }, s = { sprite = "LPBCS_g0241s", oy =   4.00 } },
    [242] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0242e", oy =   3.00 }, s = { sprite = "LPBCS_g0242s", oy =   4.00 } },
    [243] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0243e", oy =   2.00 }, s = { sprite = "LPBCS_g0243s", oy =   5.00 } },
    [244] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0244e", oy =   2.00 }, s = { sprite = "LPBCS_g0244s", oy =   4.00 } },
    [245] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0245e", oy =   2.00 }, s = { sprite = "LPBCS_g0245s", oy =   4.00 } },
    [246] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0246e", oy =   2.00 }, s = { sprite = "LPBCS_g0246s", oy =   4.00 } },
    [249] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0249e", oy =   3.00 }, s = { sprite = "LPBCS_g0249s", oy =   4.00 } },
    [250] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0250e", oy =   2.00 }, s = { sprite = "LPBCS_g0250s", oy =   5.00 } },
    [251] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0251e", oy =   2.00 }, s = { sprite = "LPBCS_g0251s", oy =   4.00 } },
    [252] = { adv =  6.00, ox =  0.00, e = { sprite = "LPBCS_g0252e", oy =   2.00 }, s = { sprite = "LPBCS_g0252s", oy =   4.00 } },
}

LPBCS.FOLD = {
    [197] = "A",        -- Å
    [198] = "AE",       -- Æ
    [208] = "D",        -- Ð
    [216] = "O",        -- Ø
    [221] = "Y",        -- Ý
    [222] = "Th",       -- Þ
    [229] = "a",        -- å
    [230] = "ae",       -- æ
    [240] = "d",        -- ð
    [248] = "o",        -- ø
    [253] = "y",        -- ý
    [254] = "th",       -- þ
    [255] = "y",        -- ÿ
    [256] = "A",        -- Ā
    [257] = "a",        -- ā
    [258] = "A",        -- Ă
    [259] = "a",        -- ă
    [260] = "A",        -- Ą
    [261] = "a",        -- ą
    [262] = "C",        -- Ć
    [263] = "c",        -- ć
    [264] = "C",        -- Ĉ
    [265] = "c",        -- ĉ
    [266] = "C",        -- Ċ
    [267] = "c",        -- ċ
    [268] = "C",        -- Č
    [269] = "c",        -- č
    [270] = "D",        -- Ď
    [271] = "d",        -- ď
    [272] = "D",        -- Đ
    [273] = "d",        -- đ
    [274] = "E",        -- Ē
    [275] = "e",        -- ē
    [276] = "E",        -- Ĕ
    [277] = "e",        -- ĕ
    [278] = "E",        -- Ė
    [279] = "e",        -- ė
    [280] = "E",        -- Ę
    [281] = "e",        -- ę
    [282] = "E",        -- Ě
    [283] = "e",        -- ě
    [284] = "G",        -- Ĝ
    [285] = "g",        -- ĝ
    [286] = "G",        -- Ğ
    [287] = "g",        -- ğ
    [288] = "G",        -- Ġ
    [289] = "g",        -- ġ
    [290] = "G",        -- Ģ
    [291] = "g",        -- ģ
    [292] = "H",        -- Ĥ
    [293] = "h",        -- ĥ
    [294] = "H",        -- Ħ
    [295] = "h",        -- ħ
    [296] = "I",        -- Ĩ
    [297] = "i",        -- ĩ
    [298] = "I",        -- Ī
    [299] = "i",        -- ī
    [300] = "I",        -- Ĭ
    [301] = "i",        -- ĭ
    [302] = "I",        -- Į
    [303] = "i",        -- į
    [304] = "I",        -- İ
    [305] = "i",        -- ı
    [308] = "J",        -- Ĵ
    [309] = "j",        -- ĵ
    [310] = "K",        -- Ķ
    [311] = "k",        -- ķ
    [312] = "k",        -- ĸ
    [313] = "L",        -- Ĺ
    [314] = "l",        -- ĺ
    [315] = "L",        -- Ļ
    [316] = "l",        -- ļ
    [317] = "L",        -- Ľ
    [318] = "l",        -- ľ
    [321] = "L",        -- Ł
    [322] = "l",        -- ł
    [323] = "N",        -- Ń
    [324] = "n",        -- ń
    [325] = "N",        -- Ņ
    [326] = "n",        -- ņ
    [327] = "N",        -- Ň
    [328] = "n",        -- ň
    [332] = "O",        -- Ō
    [333] = "o",        -- ō
    [334] = "O",        -- Ŏ
    [335] = "o",        -- ŏ
    [336] = "O",        -- Ő
    [337] = "o",        -- ő
    [338] = "OE",       -- Œ
    [339] = "oe",       -- œ
    [340] = "R",        -- Ŕ
    [341] = "r",        -- ŕ
    [342] = "R",        -- Ŗ
    [343] = "r",        -- ŗ
    [344] = "R",        -- Ř
    [345] = "r",        -- ř
    [346] = "S",        -- Ś
    [347] = "s",        -- ś
    [348] = "S",        -- Ŝ
    [349] = "s",        -- ŝ
    [350] = "S",        -- Ş
    [351] = "s",        -- ş
    [352] = "S",        -- Š
    [353] = "s",        -- š
    [354] = "T",        -- Ţ
    [355] = "t",        -- ţ
    [356] = "T",        -- Ť
    [357] = "t",        -- ť
    [358] = "T",        -- Ŧ
    [359] = "t",        -- ŧ
    [360] = "U",        -- Ũ
    [361] = "u",        -- ũ
    [362] = "U",        -- Ū
    [363] = "u",        -- ū
    [364] = "U",        -- Ŭ
    [365] = "u",        -- ŭ
    [366] = "U",        -- Ů
    [367] = "u",        -- ů
    [368] = "U",        -- Ű
    [369] = "u",        -- ű
    [370] = "U",        -- Ų
    [371] = "u",        -- ų
    [372] = "W",        -- Ŵ
    [373] = "w",        -- ŵ
    [374] = "Y",        -- Ŷ
    [375] = "y",        -- ŷ
    [376] = "Y",        -- Ÿ
    [377] = "Z",        -- Ź
    [378] = "z",        -- ź
    [379] = "Z",        -- Ż
    [380] = "z",        -- ż
    [381] = "Z",        -- Ž
    [382] = "z",        -- ž
    [399] = "E",        -- Ə
    [416] = "O",        -- Ơ
    [417] = "o",        -- ơ
    [431] = "U",        -- Ư
    [432] = "u",        -- ư
    [461] = "A",        -- Ǎ
    [462] = "a",        -- ǎ
    [463] = "I",        -- Ǐ
    [464] = "i",        -- ǐ
    [465] = "O",        -- Ǒ
    [466] = "o",        -- ǒ
    [467] = "U",        -- Ǔ
    [468] = "u",        -- ǔ
    [469] = "U",        -- Ǖ
    [470] = "u",        -- ǖ
    [471] = "U",        -- Ǘ
    [472] = "u",        -- ǘ
    [473] = "U",        -- Ǚ
    [474] = "u",        -- ǚ
    [475] = "U",        -- Ǜ
    [476] = "u",        -- ǜ
    [478] = "A",        -- Ǟ
    [479] = "a",        -- ǟ
    [480] = "A",        -- Ǡ
    [481] = "a",        -- ǡ
    [486] = "G",        -- Ǧ
    [487] = "g",        -- ǧ
    [488] = "K",        -- Ǩ
    [489] = "k",        -- ǩ
    [490] = "O",        -- Ǫ
    [491] = "o",        -- ǫ
    [492] = "O",        -- Ǭ
    [493] = "o",        -- ǭ
    [496] = "j",        -- ǰ
    [500] = "G",        -- Ǵ
    [501] = "g",        -- ǵ
    [504] = "N",        -- Ǹ
    [505] = "n",        -- ǹ
    [506] = "A",        -- Ǻ
    [507] = "a",        -- ǻ
    [512] = "A",        -- Ȁ
    [513] = "a",        -- ȁ
    [514] = "A",        -- Ȃ
    [515] = "a",        -- ȃ
    [516] = "E",        -- Ȅ
    [517] = "e",        -- ȅ
    [518] = "E",        -- Ȇ
    [519] = "e",        -- ȇ
    [520] = "I",        -- Ȉ
    [521] = "i",        -- ȉ
    [522] = "I",        -- Ȋ
    [523] = "i",        -- ȋ
    [524] = "O",        -- Ȍ
    [525] = "o",        -- ȍ
    [526] = "O",        -- Ȏ
    [527] = "o",        -- ȏ
    [528] = "R",        -- Ȑ
    [529] = "r",        -- ȑ
    [530] = "R",        -- Ȓ
    [531] = "r",        -- ȓ
    [532] = "U",        -- Ȕ
    [533] = "u",        -- ȕ
    [534] = "U",        -- Ȗ
    [535] = "u",        -- ȗ
    [536] = "S",        -- Ș
    [537] = "s",        -- ș
    [538] = "T",        -- Ț
    [539] = "t",        -- ț
    [542] = "H",        -- Ȟ
    [543] = "h",        -- ȟ
    [550] = "A",        -- Ȧ
    [551] = "a",        -- ȧ
    [552] = "E",        -- Ȩ
    [553] = "e",        -- ȩ
    [554] = "O",        -- Ȫ
    [555] = "o",        -- ȫ
    [556] = "O",        -- Ȭ
    [557] = "o",        -- ȭ
    [558] = "O",        -- Ȯ
    [559] = "o",        -- ȯ
    [560] = "O",        -- Ȱ
    [561] = "o",        -- ȱ
    [562] = "Y",        -- Ȳ
    [563] = "y",        -- ȳ
    [601] = "e",        -- ə
    [7838] = "ss",      -- ẞ
}

LPBCS.PLANKS = {
    plank = {
        e = {
            [16] = "LPBCS_pe_plank_16",
            [20] = "LPBCS_pe_plank_20",
            [24] = "LPBCS_pe_plank_24",
            [28] = "LPBCS_pe_plank_28",
            [32] = "LPBCS_pe_plank_32",
            [36] = "LPBCS_pe_plank_36",
            [40] = "LPBCS_pe_plank_40",
            [44] = "LPBCS_pe_plank_44",
            [48] = "LPBCS_pe_plank_48",
            [52] = "LPBCS_pe_plank_52",
            [56] = "LPBCS_pe_plank_56",
            [60] = "LPBCS_pe_plank_60",
            [64] = "LPBCS_pe_plank_64",
            [68] = "LPBCS_pe_plank_68",
            [72] = "LPBCS_pe_plank_72",
            [76] = "LPBCS_pe_plank_76",
            [80] = "LPBCS_pe_plank_80",
            [84] = "LPBCS_pe_plank_84",
            [88] = "LPBCS_pe_plank_88",
        },
        s = {
            [16] = "LPBCS_ps_plank_16",
            [20] = "LPBCS_ps_plank_20",
            [24] = "LPBCS_ps_plank_24",
            [28] = "LPBCS_ps_plank_28",
            [32] = "LPBCS_ps_plank_32",
            [36] = "LPBCS_ps_plank_36",
            [40] = "LPBCS_ps_plank_40",
            [44] = "LPBCS_ps_plank_44",
            [48] = "LPBCS_ps_plank_48",
            [52] = "LPBCS_ps_plank_52",
            [56] = "LPBCS_ps_plank_56",
            [60] = "LPBCS_ps_plank_60",
            [64] = "LPBCS_ps_plank_64",
            [68] = "LPBCS_ps_plank_68",
            [72] = "LPBCS_ps_plank_72",
            [76] = "LPBCS_ps_plank_76",
            [80] = "LPBCS_ps_plank_80",
            [84] = "LPBCS_ps_plank_84",
            [88] = "LPBCS_ps_plank_88",
        },
    },
    paper = {
        e = {
            [16] = "LPBCS_pe_paper_16",
            [20] = "LPBCS_pe_paper_20",
            [24] = "LPBCS_pe_paper_24",
            [28] = "LPBCS_pe_paper_28",
            [32] = "LPBCS_pe_paper_32",
            [36] = "LPBCS_pe_paper_36",
            [40] = "LPBCS_pe_paper_40",
            [44] = "LPBCS_pe_paper_44",
            [48] = "LPBCS_pe_paper_48",
            [52] = "LPBCS_pe_paper_52",
            [56] = "LPBCS_pe_paper_56",
            [60] = "LPBCS_pe_paper_60",
            [64] = "LPBCS_pe_paper_64",
            [68] = "LPBCS_pe_paper_68",
            [72] = "LPBCS_pe_paper_72",
            [76] = "LPBCS_pe_paper_76",
            [80] = "LPBCS_pe_paper_80",
            [84] = "LPBCS_pe_paper_84",
            [88] = "LPBCS_pe_paper_88",
        },
        s = {
            [16] = "LPBCS_ps_paper_16",
            [20] = "LPBCS_ps_paper_20",
            [24] = "LPBCS_ps_paper_24",
            [28] = "LPBCS_ps_paper_28",
            [32] = "LPBCS_ps_paper_32",
            [36] = "LPBCS_ps_paper_36",
            [40] = "LPBCS_ps_paper_40",
            [44] = "LPBCS_ps_paper_44",
            [48] = "LPBCS_ps_paper_48",
            [52] = "LPBCS_ps_paper_52",
            [56] = "LPBCS_ps_paper_56",
            [60] = "LPBCS_ps_paper_60",
            [64] = "LPBCS_ps_paper_64",
            [68] = "LPBCS_ps_paper_68",
            [72] = "LPBCS_ps_paper_72",
            [76] = "LPBCS_ps_paper_76",
            [80] = "LPBCS_ps_paper_80",
            [84] = "LPBCS_ps_paper_84",
            [88] = "LPBCS_ps_paper_88",
        },
    },
    painted = {
        e = {
            [16] = "LPBCS_pe_painted_16",
            [20] = "LPBCS_pe_painted_20",
            [24] = "LPBCS_pe_painted_24",
            [28] = "LPBCS_pe_painted_28",
            [32] = "LPBCS_pe_painted_32",
            [36] = "LPBCS_pe_painted_36",
            [40] = "LPBCS_pe_painted_40",
            [44] = "LPBCS_pe_painted_44",
            [48] = "LPBCS_pe_painted_48",
            [52] = "LPBCS_pe_painted_52",
            [56] = "LPBCS_pe_painted_56",
            [60] = "LPBCS_pe_painted_60",
            [64] = "LPBCS_pe_painted_64",
            [68] = "LPBCS_pe_painted_68",
            [72] = "LPBCS_pe_painted_72",
            [76] = "LPBCS_pe_painted_76",
            [80] = "LPBCS_pe_painted_80",
            [84] = "LPBCS_pe_painted_84",
            [88] = "LPBCS_pe_painted_88",
        },
        s = {
            [16] = "LPBCS_ps_painted_16",
            [20] = "LPBCS_ps_painted_20",
            [24] = "LPBCS_ps_painted_24",
            [28] = "LPBCS_ps_painted_28",
            [32] = "LPBCS_ps_painted_32",
            [36] = "LPBCS_ps_painted_36",
            [40] = "LPBCS_ps_painted_40",
            [44] = "LPBCS_ps_painted_44",
            [48] = "LPBCS_ps_painted_48",
            [52] = "LPBCS_ps_painted_52",
            [56] = "LPBCS_ps_painted_56",
            [60] = "LPBCS_ps_painted_60",
            [64] = "LPBCS_ps_painted_64",
            [68] = "LPBCS_ps_painted_68",
            [72] = "LPBCS_ps_painted_72",
            [76] = "LPBCS_ps_painted_76",
            [80] = "LPBCS_ps_painted_80",
            [84] = "LPBCS_ps_painted_84",
            [88] = "LPBCS_ps_painted_88",
        },
    },
}

LPBCS.PLANKS2 = {
    plank = {
        e = {
            [16] = "LPBCS_p2e_plank_16",
            [20] = "LPBCS_p2e_plank_20",
            [24] = "LPBCS_p2e_plank_24",
            [28] = "LPBCS_p2e_plank_28",
            [32] = "LPBCS_p2e_plank_32",
            [36] = "LPBCS_p2e_plank_36",
            [40] = "LPBCS_p2e_plank_40",
            [44] = "LPBCS_p2e_plank_44",
            [48] = "LPBCS_p2e_plank_48",
            [52] = "LPBCS_p2e_plank_52",
            [56] = "LPBCS_p2e_plank_56",
            [60] = "LPBCS_p2e_plank_60",
            [64] = "LPBCS_p2e_plank_64",
            [68] = "LPBCS_p2e_plank_68",
            [72] = "LPBCS_p2e_plank_72",
            [76] = "LPBCS_p2e_plank_76",
            [80] = "LPBCS_p2e_plank_80",
            [84] = "LPBCS_p2e_plank_84",
            [88] = "LPBCS_p2e_plank_88",
        },
        s = {
            [16] = "LPBCS_p2s_plank_16",
            [20] = "LPBCS_p2s_plank_20",
            [24] = "LPBCS_p2s_plank_24",
            [28] = "LPBCS_p2s_plank_28",
            [32] = "LPBCS_p2s_plank_32",
            [36] = "LPBCS_p2s_plank_36",
            [40] = "LPBCS_p2s_plank_40",
            [44] = "LPBCS_p2s_plank_44",
            [48] = "LPBCS_p2s_plank_48",
            [52] = "LPBCS_p2s_plank_52",
            [56] = "LPBCS_p2s_plank_56",
            [60] = "LPBCS_p2s_plank_60",
            [64] = "LPBCS_p2s_plank_64",
            [68] = "LPBCS_p2s_plank_68",
            [72] = "LPBCS_p2s_plank_72",
            [76] = "LPBCS_p2s_plank_76",
            [80] = "LPBCS_p2s_plank_80",
            [84] = "LPBCS_p2s_plank_84",
            [88] = "LPBCS_p2s_plank_88",
        },
    },
    paper = {
        e = {
            [16] = "LPBCS_p2e_paper_16",
            [20] = "LPBCS_p2e_paper_20",
            [24] = "LPBCS_p2e_paper_24",
            [28] = "LPBCS_p2e_paper_28",
            [32] = "LPBCS_p2e_paper_32",
            [36] = "LPBCS_p2e_paper_36",
            [40] = "LPBCS_p2e_paper_40",
            [44] = "LPBCS_p2e_paper_44",
            [48] = "LPBCS_p2e_paper_48",
            [52] = "LPBCS_p2e_paper_52",
            [56] = "LPBCS_p2e_paper_56",
            [60] = "LPBCS_p2e_paper_60",
            [64] = "LPBCS_p2e_paper_64",
            [68] = "LPBCS_p2e_paper_68",
            [72] = "LPBCS_p2e_paper_72",
            [76] = "LPBCS_p2e_paper_76",
            [80] = "LPBCS_p2e_paper_80",
            [84] = "LPBCS_p2e_paper_84",
            [88] = "LPBCS_p2e_paper_88",
        },
        s = {
            [16] = "LPBCS_p2s_paper_16",
            [20] = "LPBCS_p2s_paper_20",
            [24] = "LPBCS_p2s_paper_24",
            [28] = "LPBCS_p2s_paper_28",
            [32] = "LPBCS_p2s_paper_32",
            [36] = "LPBCS_p2s_paper_36",
            [40] = "LPBCS_p2s_paper_40",
            [44] = "LPBCS_p2s_paper_44",
            [48] = "LPBCS_p2s_paper_48",
            [52] = "LPBCS_p2s_paper_52",
            [56] = "LPBCS_p2s_paper_56",
            [60] = "LPBCS_p2s_paper_60",
            [64] = "LPBCS_p2s_paper_64",
            [68] = "LPBCS_p2s_paper_68",
            [72] = "LPBCS_p2s_paper_72",
            [76] = "LPBCS_p2s_paper_76",
            [80] = "LPBCS_p2s_paper_80",
            [84] = "LPBCS_p2s_paper_84",
            [88] = "LPBCS_p2s_paper_88",
        },
    },
    painted = {
        e = {
            [16] = "LPBCS_p2e_painted_16",
            [20] = "LPBCS_p2e_painted_20",
            [24] = "LPBCS_p2e_painted_24",
            [28] = "LPBCS_p2e_painted_28",
            [32] = "LPBCS_p2e_painted_32",
            [36] = "LPBCS_p2e_painted_36",
            [40] = "LPBCS_p2e_painted_40",
            [44] = "LPBCS_p2e_painted_44",
            [48] = "LPBCS_p2e_painted_48",
            [52] = "LPBCS_p2e_painted_52",
            [56] = "LPBCS_p2e_painted_56",
            [60] = "LPBCS_p2e_painted_60",
            [64] = "LPBCS_p2e_painted_64",
            [68] = "LPBCS_p2e_painted_68",
            [72] = "LPBCS_p2e_painted_72",
            [76] = "LPBCS_p2e_painted_76",
            [80] = "LPBCS_p2e_painted_80",
            [84] = "LPBCS_p2e_painted_84",
            [88] = "LPBCS_p2e_painted_88",
        },
        s = {
            [16] = "LPBCS_p2s_painted_16",
            [20] = "LPBCS_p2s_painted_20",
            [24] = "LPBCS_p2s_painted_24",
            [28] = "LPBCS_p2s_painted_28",
            [32] = "LPBCS_p2s_painted_32",
            [36] = "LPBCS_p2s_painted_36",
            [40] = "LPBCS_p2s_painted_40",
            [44] = "LPBCS_p2s_painted_44",
            [48] = "LPBCS_p2s_painted_48",
            [52] = "LPBCS_p2s_painted_52",
            [56] = "LPBCS_p2s_painted_56",
            [60] = "LPBCS_p2s_painted_60",
            [64] = "LPBCS_p2s_painted_64",
            [68] = "LPBCS_p2s_painted_68",
            [72] = "LPBCS_p2s_painted_72",
            [76] = "LPBCS_p2s_painted_76",
            [80] = "LPBCS_p2s_painted_80",
            [84] = "LPBCS_p2s_painted_84",
            [88] = "LPBCS_p2s_painted_88",
        },
    },
}

LPBCS.PLANKS3 = {
    plank = {
        e = {
            [16] = "LPBCS_p3e_plank_16",
            [20] = "LPBCS_p3e_plank_20",
            [24] = "LPBCS_p3e_plank_24",
            [28] = "LPBCS_p3e_plank_28",
            [32] = "LPBCS_p3e_plank_32",
            [36] = "LPBCS_p3e_plank_36",
            [40] = "LPBCS_p3e_plank_40",
            [44] = "LPBCS_p3e_plank_44",
            [48] = "LPBCS_p3e_plank_48",
            [52] = "LPBCS_p3e_plank_52",
            [56] = "LPBCS_p3e_plank_56",
            [60] = "LPBCS_p3e_plank_60",
            [64] = "LPBCS_p3e_plank_64",
            [68] = "LPBCS_p3e_plank_68",
            [72] = "LPBCS_p3e_plank_72",
            [76] = "LPBCS_p3e_plank_76",
            [80] = "LPBCS_p3e_plank_80",
            [84] = "LPBCS_p3e_plank_84",
            [88] = "LPBCS_p3e_plank_88",
        },
        s = {
            [16] = "LPBCS_p3s_plank_16",
            [20] = "LPBCS_p3s_plank_20",
            [24] = "LPBCS_p3s_plank_24",
            [28] = "LPBCS_p3s_plank_28",
            [32] = "LPBCS_p3s_plank_32",
            [36] = "LPBCS_p3s_plank_36",
            [40] = "LPBCS_p3s_plank_40",
            [44] = "LPBCS_p3s_plank_44",
            [48] = "LPBCS_p3s_plank_48",
            [52] = "LPBCS_p3s_plank_52",
            [56] = "LPBCS_p3s_plank_56",
            [60] = "LPBCS_p3s_plank_60",
            [64] = "LPBCS_p3s_plank_64",
            [68] = "LPBCS_p3s_plank_68",
            [72] = "LPBCS_p3s_plank_72",
            [76] = "LPBCS_p3s_plank_76",
            [80] = "LPBCS_p3s_plank_80",
            [84] = "LPBCS_p3s_plank_84",
            [88] = "LPBCS_p3s_plank_88",
        },
    },
    paper = {
        e = {
            [16] = "LPBCS_p3e_paper_16",
            [20] = "LPBCS_p3e_paper_20",
            [24] = "LPBCS_p3e_paper_24",
            [28] = "LPBCS_p3e_paper_28",
            [32] = "LPBCS_p3e_paper_32",
            [36] = "LPBCS_p3e_paper_36",
            [40] = "LPBCS_p3e_paper_40",
            [44] = "LPBCS_p3e_paper_44",
            [48] = "LPBCS_p3e_paper_48",
            [52] = "LPBCS_p3e_paper_52",
            [56] = "LPBCS_p3e_paper_56",
            [60] = "LPBCS_p3e_paper_60",
            [64] = "LPBCS_p3e_paper_64",
            [68] = "LPBCS_p3e_paper_68",
            [72] = "LPBCS_p3e_paper_72",
            [76] = "LPBCS_p3e_paper_76",
            [80] = "LPBCS_p3e_paper_80",
            [84] = "LPBCS_p3e_paper_84",
            [88] = "LPBCS_p3e_paper_88",
        },
        s = {
            [16] = "LPBCS_p3s_paper_16",
            [20] = "LPBCS_p3s_paper_20",
            [24] = "LPBCS_p3s_paper_24",
            [28] = "LPBCS_p3s_paper_28",
            [32] = "LPBCS_p3s_paper_32",
            [36] = "LPBCS_p3s_paper_36",
            [40] = "LPBCS_p3s_paper_40",
            [44] = "LPBCS_p3s_paper_44",
            [48] = "LPBCS_p3s_paper_48",
            [52] = "LPBCS_p3s_paper_52",
            [56] = "LPBCS_p3s_paper_56",
            [60] = "LPBCS_p3s_paper_60",
            [64] = "LPBCS_p3s_paper_64",
            [68] = "LPBCS_p3s_paper_68",
            [72] = "LPBCS_p3s_paper_72",
            [76] = "LPBCS_p3s_paper_76",
            [80] = "LPBCS_p3s_paper_80",
            [84] = "LPBCS_p3s_paper_84",
            [88] = "LPBCS_p3s_paper_88",
        },
    },
    painted = {
        e = {
            [16] = "LPBCS_p3e_painted_16",
            [20] = "LPBCS_p3e_painted_20",
            [24] = "LPBCS_p3e_painted_24",
            [28] = "LPBCS_p3e_painted_28",
            [32] = "LPBCS_p3e_painted_32",
            [36] = "LPBCS_p3e_painted_36",
            [40] = "LPBCS_p3e_painted_40",
            [44] = "LPBCS_p3e_painted_44",
            [48] = "LPBCS_p3e_painted_48",
            [52] = "LPBCS_p3e_painted_52",
            [56] = "LPBCS_p3e_painted_56",
            [60] = "LPBCS_p3e_painted_60",
            [64] = "LPBCS_p3e_painted_64",
            [68] = "LPBCS_p3e_painted_68",
            [72] = "LPBCS_p3e_painted_72",
            [76] = "LPBCS_p3e_painted_76",
            [80] = "LPBCS_p3e_painted_80",
            [84] = "LPBCS_p3e_painted_84",
            [88] = "LPBCS_p3e_painted_88",
        },
        s = {
            [16] = "LPBCS_p3s_painted_16",
            [20] = "LPBCS_p3s_painted_20",
            [24] = "LPBCS_p3s_painted_24",
            [28] = "LPBCS_p3s_painted_28",
            [32] = "LPBCS_p3s_painted_32",
            [36] = "LPBCS_p3s_painted_36",
            [40] = "LPBCS_p3s_painted_40",
            [44] = "LPBCS_p3s_painted_44",
            [48] = "LPBCS_p3s_painted_48",
            [52] = "LPBCS_p3s_painted_52",
            [56] = "LPBCS_p3s_painted_56",
            [60] = "LPBCS_p3s_painted_60",
            [64] = "LPBCS_p3s_painted_64",
            [68] = "LPBCS_p3s_painted_68",
            [72] = "LPBCS_p3s_painted_72",
            [76] = "LPBCS_p3s_painted_76",
            [80] = "LPBCS_p3s_painted_80",
            [84] = "LPBCS_p3s_painted_84",
            [88] = "LPBCS_p3s_painted_88",
        },
    },
}

return LPBCS.GLYPHS
