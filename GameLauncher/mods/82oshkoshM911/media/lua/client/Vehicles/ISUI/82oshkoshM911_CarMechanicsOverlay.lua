require "DAMN_MechOverlay";
--
--##########82oshkoshM911##########
--
DAMN.MechOverlay:addParts({
    ["Base.82oshkoshM911"] = "82oshkoshM911_",
    ["Base.82oshkoshM911B"] = "82oshkoshM911_",
}, {
    Battery = {img="battery",  x=224,y=91,x2=268,y2=125},
    --
    SuspensionFrontLeft = {img="suspension_front_left", x=14,y=132,x2=55,y2=170},
    SuspensionFrontRight = {img="suspension_front_right", x=228,y=132,x2=268,y2=170},
    SuspensionRearLeft = {img="suspension_rear_left", x=14,y=412,x2=55,y2=450},
    SuspensionRearRight = {img="suspension_rear_right", x=228,y=483,x2=268,y2=520},
    --
    BrakeFrontLeft = {img="brake_front_left", x=14,y=170,x2=55,y2=208},
    BrakeFrontRight = {img="brake_front_right", x=228,y=170,x2=268,y2=208},
    BrakeRearLeft = {img="brake_rear_left", x=14,y=450,x2=55,y2=488},
    BrakeRearRight = {img="brake_rear_right", x=228,y=520,x2=268,y2=560},
    --
    HeadlightLeft = {img="headlight_left", x=93,y=115,x2=107,y2=127},
    HeadlightRight = {img="headlight_right", x=176,y=115,x2=189,y2=127},
    --
    Engine = {img="engine", x=107,y=132,x2=141,y2=208},
    --
    EngineDoor = {img="hood", x=141,y=132,x2=175,y2=208},
    --
    GasTank = {img="gastank", x=211,y=340,x2=269,y2=378},
    --
    Muffler = {img="muffler", x=232,y=265,x2=268,y2=334},
    --
    TireFrontLeft = {img="wheel_front_left", x=83,y=158,x2=104,y2=207},
    TireFrontRight = {img="wheel_front_right", x=178,y=158,x2=198,y2=207},
    TireRearLeft = {img="wheel_rear_left", x=68,y=415,x2=213,y2=485},
    TireRearRight = {img="wheel_rear_right", x=68,y=485,x2=213,y2=555},
    --
    TrunkDoor = {img="trunk", x=77,y=237,x2=95,y2=298},
    --
    WindowFrontLeft = {img="window_front_left", x=95,y=218,x2=108,y2=263},
    WindowFrontRight = {img="window_front_right", x=175,y=218,x2=188,y2=263},
    --
    Windshield = {img="window_windshield", x=108,y=208,x2=175,y2=218},
    WindshieldRear = {img="window_rear_windshield", x=115,y=274,x2=167,y2=281},
    --
    M911Bullbar = {img="bull", x=34,y=27,x2=77,y2=65},
    M911WindshieldArmor = {img="winda", x=77,y=27,x2=119,y2=65},
    M911DoorFrontLeftArmor = {img="fla", x=119,y=27,x2=162,y2=65},
    M911DoorFrontRightArmor = {img="fra", x=162,y=27,x2=206,y2=65},
    M911WindshieldRearArmor = {img="rwinda", x=206,y=27,x2=248,y2=65},
}, 10, 0);
--
--##########82oshkoshTrailers##########
--
DAMN.MechOverlay:addParts({
    ["Base.TrailerM127stake"] = "TrailerM127stake_",
    ["Base.TrailerM128van"] = "TrailerM128van_",
    ["Base.TrailerM129van"] = "TrailerM129van_",
    ["Base.TrailerM747lowbed"] = "TrailerM747lowbed_",
    ["Base.TrailerM967tanker"] = "TrailerM967tanker_",
}, {}, 10, 0);