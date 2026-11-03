--***********************************************************
--**                   KI5 / bikinihorst                   **
--***********************************************************

require "Hooks/DAMN_EnterAnimations";
require "Hooks/DAMN_SemiAttachmentHelper";

DAMN = DAMN or {};
M911 = M911 or {};

DAMN.EnterAnimations:registerVehicleScript("Base.82oshkoshM911", "basic");
DAMN.EnterAnimations:registerVehicleScript("Base.82oshkoshM911B", "basic");

DAMN.SemiAttachmentHelper:registerVehicleScript("Base.82oshkoshM911", {});
DAMN.SemiAttachmentHelper:registerVehicleScript("Base.82oshkoshM911B", {});