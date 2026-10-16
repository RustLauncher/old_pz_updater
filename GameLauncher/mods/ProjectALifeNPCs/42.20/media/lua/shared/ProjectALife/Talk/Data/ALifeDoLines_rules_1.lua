ProjectALife = ProjectALife or {}
ProjectALife.DoLineShards = ProjectALife.DoLineShards or {}
ProjectALife.DoLineShards["rules_1"] = {
{"angry","in=DOOR_LEAVE_RUDE,DOOR_BLUFF"},
{"angry","in=DOOR_LEAVE,GUEST_LEAVE|tr=hates"},
{"desperate","in=DOOR_LEAVE,GUEST_LEAVE|nd=food,meds,shelter,safety,help"},
{"resigned","in=DOOR_LEAVE,GUEST_LEAVE"},
{"desperate","out=refused|nd=food,meds,shelter,safety,help"},
{"angry","out=refused|tr=hates,wary"},
{"grateful","out=gave"},
{"relieved","out=disarmed,invited"},
{"suspicious","out=searched"},
{"hopeful","out=answered|tr=warm,friend"},
{"scared","nd=safety"},
{"hurt","nd=meds"},
{"hungry","nd=food"},
{"weary","nd=shelter"},
{"formal","nd=duty"},
{"cold","mood=cold"},
{"suspicious","tr=hates,wary"},
{"easy","tr=warm,friend"},
{"nervous",""},
}
