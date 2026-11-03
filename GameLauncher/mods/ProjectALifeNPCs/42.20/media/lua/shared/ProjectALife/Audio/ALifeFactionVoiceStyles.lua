ProjectALife = ProjectALife or {}

local Styles = {

    factions = {
        alife_drifters = "drifter",
        alife_blacktop = "raider",
        alife_ashguard = "mercenary",

        alife_stillwater = "trapper",
        alife_kettle = "gang",
        alife_guard = "military",
        alife_cordon = "military",
        alife_police = "deputy",
        alife_fire = "rescue",
        alife_riverside = "holdout",

    },

    carefulLadder = { "CAREFUL_KEEP_BACK", "CAREFUL_LAST_WARNING", "CAREFUL_HOSTILE" },

    shoutEvents = { friendly = "SHOUT_FRIENDLY", neutral = "SHOUT_NEUTRAL",
        careful = "SHOUT_CAREFUL", hostile = "SHOUT_HOSTILE" },
    lines = {},
}
ProjectALife.FactionVoiceStyles = Styles

Styles.lines.drifter = {
    CONTACT_PLAYER = { "Hey, somebody's out there. Keep an eye on them",
        "Live one. Might be carrying food.", "Somebody there. Wonder what they want" },
    CONTACT_INFECTED = { "Dead ones! Watch out!", "They're up, they're up -- back off!" },
    CONTACT_HOSTILE = { "That's not ours. That's not ours!", "Watch that one. I don't like this" },
    HURT = { "I'm hit! God, I'm hit!", "It's in my side!" },
    ALLY_HIT = { "Are you hurt? Stay with me!", "Hold it, hold the wound!" },
    HIT_CONFIRMED = { "That landed! Don't get careless!", "I hit them! I actually hit them!" },
    ALLY_DOWN = { "One of ours is down! Somebody help!", "They're down! Stay with them!" },
    RETREAT = { "No no no -- run!", "Leave it! Leave the bags, go!" },
    RELOAD = { "Reloading, cover me, cover me!", "Empty -- give me a second!" },
    OUT_OF_AMMO = { "That's everything I had!", "I've got nothing left!" },
    WEAPON_JAM = { "Piece of junk jammed!", "It won't fire!" },
    BREACH = { "Get it open, come on!", "Stand back a little, give me room" },
    KILL_CONFIRMED = { "He's done. Check his pockets.", "Down. Take what he's got." },
    LOST_TARGET = { "Where'd they go? Anyone see?", "Lost them. Damn it." },
    SEARCH_START = { "Spread out, check around.", "Look around. Keep your eyes open." },
    ORDER_ACK = { "Yeah, alright.", "Going, going.", "Fine, I'm on it." },
    WARNING_STOP = { "Stop there! I mean it!", "Don't -- just stay where you are!" },
    WARNING_LOWER_WEAPON = { "Put it down and we're fine!", "Lower it! Lower it!" },
    IDLE = { "I hate waiting without knowing what's next", "I keep hoping we'll find something worth the walk" },
    PANIC = { "Easy! Keep your distance!", "Scatter! Get off the road!" },
    STEADY = { "Stand still. We're not dying here today.", "Breathe. They're just people." },
    SUPPRESS_FIRE = { "Keep your head down, whoever you are!", "Firing! Just keep firing!" },
    SUPPORT_CALL = { "Anybody on this channel, we need bodies!", "Call the yard, tell them it went bad!" },
    REGROUP = { "Back to me, back to me!", "Together! Don't run off alone!" },
    MOVE_OUT = { "Come on, before something hears us.", "Let's go, but keep looking" },
    CAREFUL_KEEP_BACK = { "That's close enough, friend.", "Keep your distance and nobody gets hurt.",
        "Stay back. We've had a bad week." },
    CAREFUL_LAST_WARNING = { "I said BACK. Next step I shoot!", "Don't test me, I'm out of patience!" },
    CAREFUL_HOSTILE = { "You wanted it -- take {him}!", "That's it! Drop {him}!" },
    SHOUT_FRIENDLY = { "Over here! Friendly, don't shoot!", "Hey! Hey, it's us -- come on over!", "Good to hear a voice. Come sit." },
    SHOUT_NEUTRAL = { "Keep it down! I don't want anything coming to look", "Who's yelling? Shut up before something hears!", "Easy with the noise, stranger. Nothing personal." },
    SHOUT_CAREFUL = { "Yelling won't get you closer. Stay where you are!", "We hear you. Now stop and stay over there!", "Don't come shouting at us. Keep back!" },
    SHOUT_HOSTILE = { "{he}'s out there! That way!", "Somebody's calling. Go get {him}!", "Shouting's the last thing you'll do!" },
}

Styles.lines.raider = {
    CONTACT_PLAYER = { "Look at this sucker walking right into it.",
        "Hey, look who we've got here. Wonder what's worth taking", "Fresh meat on the blacktop, boys." },
    CONTACT_INFECTED = { "Dead ones. Ignore them, watch the road.", "Biters coming -- put them down quick." },
    CONTACT_HOSTILE = { "Somebody wants trouble? Good!", "Don't let that one push you around!" },
    HURT = { "You son of a -- I'm hit!", "That's coming out of your teeth!" },
    ALLY_HIT = { "You're hurt? Back up, let me see!", "Wrap it and stay in the fight!" },
    HIT_CONFIRMED = { "Tagged them! Keep watching!", "That one felt it! Don't get stupid now!" },
    ALLY_DOWN = { "They dropped one of ours! Kill them!", "He's down -- no mercy now!" },
    RETREAT = { "Fall back! Fall back!", "Pull back, regroup!" },
    RELOAD = { "Feeding it! Keep them off me!", "Reloading -- don't let them move up!" },
    OUT_OF_AMMO = { "Dry! Somebody throw me something!", "I'm out! Toss me a mag!" },
    WEAPON_JAM = { "Jammed! Piece of garbage!", "It's stuck -- cover me!" },
    BREACH = { "Take the door off!", "We're coming in whether you open it or not!" },
    KILL_CONFIRMED = { "Down. Strip him.", "That's his stuff now.", "One less problem." },
    LOST_TARGET = { "Slippery. Find him.", "Lost them. Don't let that make you careless" },
    SEARCH_START = { "Check every car, every ditch.", "Keep looking. I don't like losing track" },
    ORDER_ACK = { "Yeah yeah.", "Moving.", "On it, boss." },
    WARNING_STOP = { "Stop right there, {g:pal|lady}!", "That's far enough. Hands where I see them." },
    WARNING_LOWER_WEAPON = { "Drop it or lose the arm!", "Weapon down. Now." },
    IDLE = { "I wonder who we'll run into next", "Patience. They always come." },
    PANIC = { "Shit! Watch that stranger!", "Back up! Give me some room!" },
    STEADY = { "Nobody runs. This is OUR road.", "Hold the line or I shoot you myself." },
    SUPPRESS_FIRE = { "Stay in that hole! Eat it!", "Keep them pinned -- move up on the left!" },
    SUPPORT_CALL = { "Get the rest of the crew down here!", "Radio the camp. Tell them it's worth coming." },
    REGROUP = { "On me! Form up!", "Back together, don't wander off!" },
    MOVE_OUT = { "Roll out. Eyes open.", "We move. Stay off the middle of the road." },
    CAREFUL_KEEP_BACK = { "Whoa. Far enough, sweetheart.",
        "Get away before I mug your shit -- don't you get close!", "Stop walking. I'm being polite." },
    CAREFUL_LAST_WARNING = { "One more step and I take everything you've got, starting with your teeth!",
        "Last chance. Turn around or bleed out here!" },
    CAREFUL_HOSTILE = { "You had your warning! Take {him}!", "Alright -- {he}'s asking for it!" },
    SHOUT_FRIENDLY = { "Yo! Over here, {g:buddy|lady}!", "Ha, it's you! Get over here.", "We hear you, friend. Come on, bring the bags." },
    SHOUT_NEUTRAL = { "Shut your mouth out there!", "Want something to hear you? Keep it down, genius", "Keep hollering and we'll come find out why." },
    SHOUT_CAREFUL = { "You shout again and I take it as a yes. BACK OFF!", "Loud one. Loud ones get robbed. Stay there!", "Screaming at us? Keep walking the other way!" },
    SHOUT_HOSTILE = { "There {he} is! Get {him}, take {his} stuff!", "Hear that mouth? Let's find out what they want!", "Hear that? Free pickings. Go!" },
}

Styles.lines.gang = {
    CONTACT_PLAYER = { "Hey! Hey, somebody out here!",
        "One of them scavengers -- get him!", "There! Somebody's there! Look!" },
    CONTACT_INFECTED = { "Dead ones! Keep looking!", "Biters! Stay back!" },
    CONTACT_HOSTILE = { "Watch out! Don't just stand there!", "Fight! We got a fight!" },
    HURT = { "Aaah! I'm hit!", "Somebody help me!" },
    ALLY_HIT = { "One of ours is hurt! Help them!", "Pull him back, pull him back!" },
    HIT_CONFIRMED = { "I got one of them!", "He's hurt! Push, push!" },
    ALLY_DOWN = { "Somebody's down! Shit!", "One's down! All of you, on them!" },
    RETREAT = { "Back to the yard!", "Everybody out! Out!" },
    RELOAD = { "Loading! Somebody cover!", "Hold on, hold on -- reloading!" },
    OUT_OF_AMMO = { "Dry! I'm bone dry!", "Nothing left, give me a pipe!" },
    WEAPON_JAM = { "It's stuck! Piece of junk!", "Won't shoot! Won't shoot!" },
    BREACH = { "All of you -- push it in!", "Kick it off the hinges!" },
    KILL_CONFIRMED = { "Got him! Got him!", "He's down! Grab his stuff!" },
    LOST_TARGET = { "Where is he? Anybody?", "Spread out, but don't stop watching!" },
    SEARCH_START = { "Everybody look! Behind the sheds too!", "Keep looking! I don't know where they went!" },
    ORDER_ACK = { "Alright!", "Going!", "Yeah, yeah, I hear you." },
    WARNING_STOP = { "Oi! Stop!", "Don't come in here!" },
    WARNING_LOWER_WEAPON = { "Put that down!", "Drop it! I'm not asking again!" },
    IDLE = { "Anyone eaten today?", "I'm sick of wondering where our next meal's coming from" },
    PANIC = { "I don't like this! Back up!", "It's a fight! It's a fight!" },
    STEADY = { "Stay together! Don't leave me standing here!", "Nobody runs! We're the whole yard!" },
    SUPPRESS_FIRE = { "Shoot at it! Keep shooting!", "Don't let them lift their heads!" },
    SUPPORT_CALL = { "Get everyone from the works!", "Ring the yard bell -- all of them!" },
    REGROUP = { "Everybody here! Together!", "Group up, group up!" },
    MOVE_OUT = { "All of us, come on!", "Move! Stay in the pack!" },
    CAREFUL_KEEP_BACK = { "That's close enough, mate.", "Back up. I don't like being crowded",
        "Don't come any nearer, we're not in the mood." },
    CAREFUL_LAST_WARNING = { "I'm telling you once more -- back off!", "Next step and the whole yard's on you!" },
    CAREFUL_HOSTILE = { "Get {him}! All of you!", "{he}'s asking! Take {him} down!" },
    SHOUT_FRIENDLY = { "That's our boy! Get over here!", "Yeah, we hear you! Come through!", "Friendly voice. Roll up, {g:man|lady}." },
    SHOUT_NEUTRAL = { "Who's screaming out there? Shut it!", "Keep that noise down or we come out.", "Somebody wants attention. Not from us." },
    SHOUT_CAREFUL = { "Shout at us again and it's on. Back up!", "We heard you. Don't come closer!", "Loud and stupid. Stay on your side!" },
    SHOUT_HOSTILE = { "That way! Somebody's hollering, go get 'em!", "Heard {him}. Run {him} down!", "Mouth's loud -- let's close it!" },
}

Styles.lines.mercenary = {
    CONTACT_PLAYER = { "Someone there. Keep watching",
        "Look at that one. Don't rush into anything", "I see somebody. I don't know what they want" },
    CONTACT_INFECTED = { "Infected, my lane. Suppressing.", "Dead ones. Don't let them surprise you" },
    CONTACT_HOSTILE = { "Careful with that one. Don't get careless", "Watch out. Give each other room" },
    HURT = { "Hit. Still up.", "Took one. Still in it." },
    ALLY_HIT = { "You're hit -- rotate out, I have your lane.", "Wound check. Pressure on it, keep firing." },
    HIT_CONFIRMED = { "Hit on target.", "Solid hit. Following up." },
    ALLY_DOWN = { "Man down. Rotate.", "Somebody's down. Stay together" },
    RETREAT = { "Falling back by pairs. Cover.", "Break contact. Bounding." },
    RELOAD = { "Reloading, cover my lane.", "Changing mags -- talk to me." },
    OUT_OF_AMMO = { "Dry. Transitioning.", "Out. Give me a moment" },
    WEAPON_JAM = { "Stoppage. Clearing.", "Weapon down, working it." },
    BREACH = { "Breaching. Stack behind me.", "Door's going. Stand by." },
    KILL_CONFIRMED = { "Target down.", "Down and confirmed." },
    LOST_TARGET = { "Lost sight of them. Keep looking", "No line. Somebody call it." },
    SEARCH_START = { "Sectors. Work it methodically.", "Clear it by numbers." },
    ORDER_ACK = { "Copy.", "Acknowledged.", "Moving." },
    WARNING_STOP = { "Stop where you are. This is a controlled area.", "Stop there. That's close enough" },
    WARNING_LOWER_WEAPON = { "Lower the weapon. Slowly.", "Muzzle down. Do it now." },
    IDLE = { "I'm staying put. Keep an eye out", "I don't like waiting around like this" },
    PANIC = { "Someone there! Keep back!", "Easy! Don't rush at them!" },
    STEADY = { "Steady. Work your lane.", "Discipline. Nobody moves without a call." },
    SUPPRESS_FIRE = { "Suppressing. Move on my fire.", "Pinning them. Go now." },
    SUPPORT_CALL = { "Command, this is Ash element, requesting support.", "Calling it in. Hold what you have." },
    REGROUP = { "Rally on me. Count off.", "Consolidate. Two ranks." },
    MOVE_OUT = { "Moving. Stay in your lane.", "Step off. Interval." },
    CAREFUL_KEEP_BACK = { "That is close enough. Hold there.",
        "You are at the edge of our perimeter. Do not cross it.", "Stop. This is your first warning." },
    CAREFUL_LAST_WARNING = { "Second warning. There is no third.", "Turn around now. Don't make this worse" },
    CAREFUL_HOSTILE = { "That's enough. Back off!", "{he} crossed it. Drop {him}." },
    SHOUT_FRIENDLY = { "We hear you, friend. Come over carefully", "Copy your call. Approach slow, hands visible.", "Heard you. Come to us, we're holding." },
    SHOUT_NEUTRAL = { "Unknown, shouting. Hold your position.", "Keep it quiet. I don't want anything following your voice", "Somebody's calling. Keep an eye out" },
    SHOUT_CAREFUL = { "We hear you. Keep your distance!", "You shout, you stop. Last time I say it!", "Hold there. One more step and it's a problem." },
    SHOUT_HOSTILE = { "Target announced {himself}. Move on {him}.", "We heard you. Don't come any closer", "{he} gave us {his} position. Take it." },
}

Styles.lines.soldier = {
    CONTACT_PLAYER = { "Someone out there. Keep watching",
        "I can see someone. Take your time", "Movement front. Looks like a civilian." },
    CONTACT_INFECTED = { "Infected, front. Aimed fire only.", "Dead ones. Watch what you're doing" },
    CONTACT_HOSTILE = { "Watch that one! Keep your distance!", "I don't like this. Stay alert!" },
    HURT = { "I'm hit! Still fighting!", "Took a round -- I'm good!" },
    ALLY_HIT = { "You're hit -- get low, I've got you!", "Wound. Pressure and stay behind me!" },
    HIT_CONFIRMED = { "Hits on target!", "He's hit, keep on him!" },
    ALLY_DOWN = { "Man down! Man down!", "We lost one! Cover his position!" },
    RETREAT = { "Fall back! Bounding by pairs!", "Back away! Stay together!" },
    RELOAD = { "Reloading! Cover!", "Mag change -- talk to me!" },
    OUT_OF_AMMO = { "Black on ammo!", "I'm out! Need a resupply!" },
    WEAPON_JAM = { "Stoppage! Clearing!", "Weapon's down -- covering!" },
    BREACH = { "Breaching! Stack up!", "Making entry!" },
    KILL_CONFIRMED = { "Target neutralised.", "He's down. Scanning." },
    LOST_TARGET = { "Lost him. Last known, my front.", "No joy. Anyone have eyes?" },
    SEARCH_START = { "Sweep it. Sectors, by the numbers.", "Search pattern. Nothing skipped." },
    ORDER_ACK = { "Roger.", "Solid copy.", "Wilco." },
    WARNING_STOP = { "Halt! This is a restricted position!", "Stop where you are, {sir}!" },
    WARNING_LOWER_WEAPON = { "Lower your weapon! Do it now!", "Put the weapon on the ground!" },
    IDLE = { "Position holding. Nothing to report.", "Same as yesterday. Quiet." },
    PANIC = { "Someone there! Hold on!", "Back up! Don't crowd them!" },
    STEADY = { "Steady! Aimed fire!", "Hold your positions! On me!" },
    SUPPRESS_FIRE = { "Suppressing! Move up!", "Rate of fire up -- pin them!" },
    SUPPORT_CALL = { "Any station this net, requesting immediate support.", "Calling for backup. Hold the line." },
    REGROUP = { "Rally point, on me!", "Consolidate! Count off!" },
    MOVE_OUT = { "Move out. Interval, five metres.", "Stepping off. Eyes up." },
    CAREFUL_KEEP_BACK = { "{sir}, that is close enough. Stop there.",
        "You are approaching a manned position. Hold.", "Stop and state your business." },
    CAREFUL_LAST_WARNING = { "Final warning! Don't come any closer!", "Turn around now! This is the last time I say it!" },
    CAREFUL_HOSTILE = { "That's enough! Back off!", "Warnings given. Drop {him}." },
    SHOUT_FRIENDLY = { "Friendly! Friendly, come on in!", "Copy that, come to our position!", "Heard you loud. Stay with us." },
    SHOUT_NEUTRAL = { "Keep your voice down! I don't want more trouble!", "Stop shouting! Get to cover!", "Quiet! Don't give anything a reason to come looking!" },
    SHOUT_CAREFUL = { "Civilian, halt where you are! Do not approach!", "That's your warning -- stop and back away!", "Hold there! Shouting won't get you past us!" },
    SHOUT_HOSTILE = { "We hear you! Stay back!", "Hostile called out {his} position. Move!", "{he}'s over there -- suppress and close!" },
}

Styles.lines.military = {}
for event, entries in pairs(Styles.lines.soldier) do
    Styles.lines.military[event] = entries
end

Styles.lines.military.CAREFUL_KEEP_BACK = {
    "United States Military. Turn around and go home, civilian!",
    "Stop there! Military. Walk away!",
    "Kentucky National Guard. You are approaching a military position!",
    "This area is under military control. Go back to your house!",
    "You are walking into military operations. Turn around!",
    "Stop there. You need to keep your distance!",
    "Go back the way you came. This position is closed!",
    "{sir}, this is a restricted military area. Return to your home!",
}
Styles.lines.military.CAREFUL_LAST_WARNING = {
    "Final warning, civilian! Walk away from military operations!",
    "Get back! Go back home, now!",
    "United States Military! Leave this area or you will be fired on!",
    "Second warning. There is no third. Go home!",
    "Back away from us. Do it now!",
    "Last time, civilian. Turn around and walk!",
    "One more step and this gets ugly. Turn around!",
    "Move back before this gets worse. Your call!",
}

Styles.lines.military.CAREFUL_HOSTILE = {
    "That's it! You stay back!",
    "{he} walked through every warning. Take {him}!",
    "Don't let them push past you!",
    "I've had enough! Back off!",
    "Warnings expended. Put {him} down!",
    "Get back! I mean it!",
    "Then that's your choice! Don't come closer!",
    "Watch out! Don't let them crowd you!",
}

Styles.lines.military.WARNING_STOP = {
    "United States Military! Go back to your home, civilian!",
    "Stop there! Walk away!",
    "Turn around. This is a military position!",
    "Kentucky National Guard. Go home!",
    "Stop right there, civilian. Military operations!",
    "Get back and go back home!",
}

Styles.lines.military.SHOUT_CAREFUL = {
    "Shouting changes nothing, civilian. Turn around and go home!",
    "We hear you. Walk away from military operations!",
    "Stop where you are! Keep your distance from us!",
    "Keep the noise down and go back to your house!",
}

Styles.lines.deputy = {
    CONTACT_PLAYER = { "County unit, I've got a civilian on foot.",
        "Somebody's out here. Hands, let me see hands.", "Somebody walking up. Can't tell what he wants." },
    CONTACT_INFECTED = { "Infected in the open. Taking them.", "We've got deads. Watch your backdrop." },
    CONTACT_HOSTILE = { "Watch that one! Keep back!", "Stay alert! Don't rush in!" },
    HURT = { "Officer hit! I'm hit!", "I'm down a step -- still with you!" },
    ALLY_HIT = { "You're hit, stay with me!", "Stay with me. Let me see how bad it is" },
    HIT_CONFIRMED = { "I hit him!", "That hit! Keep watching them!" },
    ALLY_DOWN = { "Officer down! Officer down!", "We lost one! Cover me!" },
    RETREAT = { "Back up! Stay with me!", "Falling back! Cover each other!" },
    RELOAD = { "Reloading! Keep his head down!", "I'm empty, keep a lookout!" },
    OUT_OF_AMMO = { "Long gun's dry!", "Empty! Give me a second!" },
    WEAPON_JAM = { "Weapon's jammed!", "Malfunction! Clearing it!" },
    BREACH = { "County sheriff! Coming in!", "Taking the door!" },
    KILL_CONFIRMED = { "Subject is down.", "He's down. Watch the hands." },
    LOST_TARGET = { "Lost them. I don't know where they went", "He's out of sight. Somebody call it." },
    SEARCH_START = { "Check the yards and the sheds. Go slow.", "Check every door. Nothing skipped." },
    ORDER_ACK = { "Copy that.", "Ten-four.", "Understood." },
    WARNING_STOP = { "Sheriff's department! Stop right there!", "Stop! Do not take another step!" },
    WARNING_LOWER_WEAPON = { "Drop the weapon! Drop it now!", "Put it down and step away from it!" },
    IDLE = { "I miss a quiet shift that actually felt quiet", "I wish we knew who was still out there" },
    PANIC = { "Look out! Keep back!", "Someone there! Easy, easy!" },
    STEADY = { "Everybody breathe. We do this by the book.", "Hold your positions. We're still the law here." },
    SUPPRESS_FIRE = { "Keep him pinned! Move up!", "Covering fire! Go!" },
    SUPPORT_CALL = { "Dispatch, this unit requesting immediate assistance.", "Ten-thirty-three! Any unit responding!" },
    REGROUP = { "Back to me! Stay together!", "Back together! Stay close!" },
    MOVE_OUT = { "Let's roll. Eyes open.", "Moving out. Watch your corners." },
    CAREFUL_KEEP_BACK = { "{sir}, stop right there. That is close enough.",
        "Stay back. I'm not asking twice.", "Stop and keep your hands where I can see them." },
    CAREFUL_LAST_WARNING = { "This is your final warning! Back away or I fire!",
        "Any closer and I will treat you as a threat!" },
    CAREFUL_HOSTILE = { "{he} won't stop! Take the shot!", "That's it -- {he} had {his} warnings!" },
    SHOUT_FRIENDLY = { "Deputy here! Come over carefully!", "We hear you! Walk on over, easy.", "Friendly! Come to my voice." },
    SHOUT_NEUTRAL = { "{sir}, keep your voice down. I don't want trouble finding us", "Stop shouting, please. We'll come to you.", "Quiet down and stay put." },
    SHOUT_CAREFUL = { "Stay where you are! Do not come closer!", "That's enough! Back away, now!", "Shouting at us is not helping. Step back!" },
    SHOUT_HOSTILE = { "Suspect's calling out. Go, go!", "{he} wants us? {He}'s got us. Move!", "Over there -- take {him}!" },
}

Styles.lines.holdout = {
    CONTACT_PLAYER = { "Somebody's coming up the street!",
        "There's a person out front. Everyone up.", "Somebody's there. Keep an eye on them" },
    CONTACT_INFECTED = { "Dead ones! Watch out!", "Dead ones! Don't let them get too close!" },
    CONTACT_HOSTILE = { "Watch that one! Keep your distance!", "Trouble! Stay together!" },
    HURT = { "I'm hit! Oh God, I'm hit!", "It got me! It got me!" },
    ALLY_HIT = { "Are you hurt? Hold still, let me look!", "Hold still, let me see it!" },
    HIT_CONFIRMED = { "I hit one! I actually hit one!", "He's hurt, keep shooting!" },
    ALLY_DOWN = { "Somebody's down! Somebody help!", "He's down -- somebody get him inside!" },
    RETREAT = { "Inside! Everybody inside!", "Get back in the house!" },
    RELOAD = { "Reloading! Somebody keep a lookout!", "I need a second, cover me!" },
    OUT_OF_AMMO = { "I'm out of shells!", "That was my last one!" },
    WEAPON_JAM = { "It's jammed! It's jammed!", "It won't fire, I can't -- " },
    BREACH = { "Stand back! Give me some room!", "Get the door open, quickly!" },
    KILL_CONFIRMED = { "He's down. He's down, right?", "I got him. God. I got him." },
    LOST_TARGET = { "I lost him! Where is he?", "He's out of sight -- watch the back!" },
    SEARCH_START = { "Check the yard. Stay in pairs.", "Look around, but don't go far." },
    ORDER_ACK = { "Okay. Okay.", "I've got it.", "Right, doing it." },
    WARNING_STOP = { "That's close enough! Stop!", "Don't come any closer to our house!" },
    WARNING_LOWER_WEAPON = { "Put the gun down and we'll talk!", "Lower it! Please, just lower it!" },
    IDLE = { "Another quiet one. Thank God.", "I can't stop thinking about the next meal" },
    PANIC = { "Watch out! Keep back!", "Everyone down! Down!" },
    STEADY = { "Stay together. This is our home.", "Nobody panics. We've held it this long." },
    SUPPRESS_FIRE = { "Keep firing at that corner!", "Don't let them cross the street!" },
    SUPPORT_CALL = { "Try the radio! Somebody has to answer!", "Call anyone! I'd be glad of some help!" },
    REGROUP = { "Everyone back inside, now!", "Get to the stairs, together!" },
    MOVE_OUT = { "Stay close and keep quiet.", "Move. Don't wander off." },
    CAREFUL_KEEP_BACK = { "That's close enough, please. We don't want trouble.",
        "Stay where you are. We're just people trying to hold a house.",
        "Please stop there. We will defend this place." },
    CAREFUL_LAST_WARNING = { "I'm warning you -- one more step and I shoot!",
        "Please! Don't make us do this!" },
    CAREFUL_HOSTILE = { "{he} won't stop -- fire!", "Then that's on {him}! Shoot!" },
    SHOUT_FRIENDLY = { "Over here, neighbor! Come on in!", "We hear you! Come over carefully!", "Friendly! Come on, quick!" },
    SHOUT_NEUTRAL = { "Keep your voice down out there!", "Stop yelling! I don't want anything coming to look!", "Hush! We've got enough to worry about!" },
    SHOUT_CAREFUL = { "Don't come near the house! Turn around!", "I hear you. Now go away from here!", "Shout all you want, you're not coming in. Back!" },
    SHOUT_HOSTILE = { "{he}'s out front! Get {him} off the property!", "Somebody's calling. Shoot first!", "That's {him} -- take {him}!" },
}

Styles.lines.trapper = {
    CONTACT_PLAYER = { "Somebody there. Take a moment and look",
        "Got a person. Not moving like a hunter.", "One walking. Watch him a while." },
    CONTACT_INFECTED = { "Deads. Let them come to us.", "Rotters. Don't get careless" },
    CONTACT_HOSTILE = { "Careful with that one. Back away slowly", "Watch that one. Don't rush closer" },
    HURT = { "Winged me.", "I'm hit. Not bad." },
    ALLY_HIT = { "You're hurt? Stay still, let me look", "Sit down. Let me see it." },
    HIT_CONFIRMED = { "Hit him.", "That landed." },
    ALLY_DOWN = { "He's down. Back into the trees.", "We lost one. Break off." },
    RETREAT = { "Give ground. Slow.", "Back away. Keep watching" },
    RELOAD = { "Loading.", "One moment. Cover the gap." },
    OUT_OF_AMMO = { "Dry.", "Out of rounds." },
    WEAPON_JAM = { "Jam. Working it.", "Won't cycle." },
    BREACH = { "Take the window.", "Through here. Quiet." },
    KILL_CONFIRMED = { "Down.", "That's him." },
    LOST_TARGET = { "Lost sight of them", "I can't see where they went" },
    SEARCH_START = { "Look carefully. Don't assume where they went", "Track him. Slow." },
    ORDER_ACK = { "Mm.", "Heard.", "Understood." },
    WARNING_STOP = { "Far enough. Stop there.", "Stand still." },
    WARNING_LOWER_WEAPON = { "Point that somewhere else.", "Barrel down." },
    IDLE = { "I miss a day when all I had to watch for was deer", "I don't like having to second-guess every move" },
    PANIC = { "Down! Down!", "Easy. Keep back!" },
    STEADY = { "Easy. Pick your shot.", "No hurry. Breathe." },
    SUPPRESS_FIRE = { "Keeping his head down. Move.", "Keep watching them. Don't rush in" },
    SUPPORT_CALL = { "Call the camp. We need the others.", "Get somebody on the radio." },
    REGROUP = { "On me. Quiet.", "Back together. Same line." },
    MOVE_OUT = { "Walk. Don't crash through it.", "Move. Watch where you put your feet." },
    CAREFUL_KEEP_BACK = { "That's close enough. Stop walking.",
        "Keep your distance. We're not looking for company.", "Far enough, friend." },
    CAREFUL_LAST_WARNING = { "Next step, I put one through you.", "I won't say it again. Turn around." },
    CAREFUL_HOSTILE = { "Take {him}.", "{he} chose. Fire." },
    SHOUT_FRIENDLY = { "Heard you. Come.", "Over here. Slow.", "Friend. Come on." },
    SHOUT_NEUTRAL = { "Quiet.", "Shouting brings them. Hush.", "Keep walking. Quiet." },
    SHOUT_CAREFUL = { "Stay there.", "Don't come closer.", "That's far enough. Go." },
    SHOUT_HOSTILE = { "There.", "{he} told us where. Go.", "Loud one. Take {him}." },
}

Styles.lines.rescue = {
    CONTACT_PLAYER = { "Got a live one! Anybody hurt out there?",
        "Person on foot -- watch him, but nobody shoots first.", "Somebody's walking up. Stay calm." },
    CONTACT_INFECTED = { "Infected! Keep your distance!", "Deads coming. Tight formation." },
    CONTACT_HOSTILE = { "Watch out! Stay together!", "Hostiles! Cover, cover!" },
    HURT = { "I'm hit! Still standing!", "Took one -- keep working!" },
    ALLY_HIT = { "You're hit! Down, let me work!", "Stay with me! Let me see how bad it is!" },
    HIT_CONFIRMED = { "He's hit!", "That hit! Keep watching!" },
    ALLY_DOWN = { "Somebody's down! Help them!", "We've got a casualty! Cover me!" },
    RETREAT = { "Back away! Everybody together!", "Pull out! Nobody stays behind!" },
    RELOAD = { "Reloading! Watch my side!", "Second! Cover the street!" },
    OUT_OF_AMMO = { "I'm empty! Give me a moment!", "Out! Somebody else take the front!" },
    WEAPON_JAM = { "Gun's jammed! Switching!", "It's stuck! Cover me!" },
    BREACH = { "Making entry! Stand clear!", "Taking the door -- stand back!" },
    KILL_CONFIRMED = { "He's down.", "That's done. Move up." },
    LOST_TARGET = { "Lost him. Watch the alleys.", "He's out of sight -- eyes everywhere." },
    SEARCH_START = { "Search pattern, two by two. Nobody alone.", "Clear it room by room." },
    ORDER_ACK = { "Copy.", "On it.", "Got it, chief." },
    WARNING_STOP = { "Stop there! We're not looking for a fight!", "Hold it right there!" },
    WARNING_LOWER_WEAPON = { "Lower that! Nobody has to get hurt!", "Put it down and we'll help you!" },
    IDLE = { "I keep hoping we'll see the station again", "I miss turning a tap without thinking about it" },
    PANIC = { "Someone there! Easy, keep back!", "Down! Everybody down!" },
    STEADY = { "We work as one crew. Same as always.", "Steady. We've walked into worse than this." },
    SUPPRESS_FIRE = { "Keeping them down! Move the crew!", "Covering! Go, go!" },
    SUPPORT_CALL = { "Station, this is fourteen, we need help!", "Calling it in! Anybody on this channel!" },
    REGROUP = { "Together! Everyone back together!", "Crew up! Count heads!" },
    MOVE_OUT = { "Crew's moving. Stay together.", "Let's work. Eyes up." },
    CAREFUL_KEEP_BACK = { "That's close enough, {g:buddy|lady}. Stay right there.",
        "Keep your distance and we stay friendly.", "Stop there. We help people, but we don't take chances." },
    CAREFUL_LAST_WARNING = { "Last warning -- back off!", "Don't make this something it doesn't have to be!" },
    CAREFUL_HOSTILE = { "{he}'s not stopping! Take {him}!", "That's it -- put {him} down!" },
    SHOUT_FRIENDLY = { "We hear you! Help's coming, hold on!", "Over here! Come carefully!", "Friendly! Are you hurt? Come on!" },
    SHOUT_NEUTRAL = { "Keep it down, please! We're working here!", "Stop shouting, you'll draw them!", "Quiet! We'll come to you!" },
    SHOUT_CAREFUL = { "Stay back from us! Don't come closer!", "That's it -- stop where you are!", "Back away! Shouting won't change it!" },
    SHOUT_HOSTILE = { "{he}'s over there! Stop {him}!", "Somebody's calling us out. Go!", "That way -- take {him} down!" },
}

function Styles.styleFor(factionId)
    local id = tostring(factionId or "")
    local style = Styles.factions[id]
    if style ~= nil and Styles.lines[style] ~= nil then return style end
    return nil
end

function Styles.linesFor(factionId, event)
    local style = Styles.styleFor(factionId)
    if style == nil or type(event) ~= "string" then return nil end
    return Styles.lines[style][string.upper(event)]
end

Styles.lines.drifter.CAREFUL_KEEP_BACK_FIGHTING = {
    "We are a bit busy! Stay back there!",
    "Not now, stranger. Not now! Keep away!",
    "You can see what is happening. Back up and wait.",
}
Styles.lines.raider.CAREFUL_KEEP_BACK_FIGHTING = {
    "Wait your turn, friend. Stay right there.",
    "We are working. Come closer and you are next.",
    "One thing at a time. Do not move.",
}
Styles.lines.gang.CAREFUL_KEEP_BACK_FIGHTING = {
    "We got something going on. Back up, back up!",
    "Not the time. Stay off us.",
    "You see this? Then you know to keep walking.",
}
Styles.lines.mercenary.CAREFUL_KEEP_BACK_FIGHTING = {
    "We're busy here. Stay where you are",
    "We're busy here. Give us some room",
    "Stay out of it and stay back.",
}
Styles.lines.soldier.CAREFUL_KEEP_BACK_FIGHTING = {
    "Not now! Stay where you are!",
    "We're busy! Keep back!",
    "Not now. Hold there until we are clear.",
}
Styles.lines.deputy.CAREFUL_KEEP_BACK_FIGHTING = {
    "{sir}, we have a situation. Stay back.",
    "We are dealing with this. Do not come closer.",
    "Keep your distance until this is over.",
}
Styles.lines.holdout.CAREFUL_KEEP_BACK_FIGHTING = {
    "We are in the middle of something! Keep back!",
    "Not now! Stay where you are!",
    "Wait it out over there. Do not come in.",
}
Styles.lines.trapper.CAREFUL_KEEP_BACK_FIGHTING = {
    "Bit busy here. You stay put.",
    "Hold up there, we got our hands full.",
    "Give us a minute and keep your distance.",
}
Styles.lines.rescue.CAREFUL_KEEP_BACK_FIGHTING = {
    "We are working a problem. Stay clear.",
    "Hold there, we will come to you when it is safe.",
    "Keep back until we have this handled.",
}
Styles.lines.military.CAREFUL_KEEP_BACK_FIGHTING = {
    "We're busy. Keep your distance",
    "Not now. Stay back and give us room",
    "Stand by there until this position is clear.",
}

ProjectALife.FactionVoiceRegister = function(Catalog)
    if type(Catalog) ~= "table" or Catalog.factionStylesLoaded then return end
    Catalog.factionStylesLoaded = true

    local Library = ProjectALife.ReactionLibrary
    local defaults = Library and Library.defaults and Library.defaults.combat or {}
    local ladder = {
        CAREFUL_KEEP_BACK = { priority = 84, chance = 100, cooldownMs = 9000,
            groupCooldownMs = 3000, actorLockMs = 1900 },

        CAREFUL_KEEP_BACK_FIGHTING = { priority = 82, chance = 100, cooldownMs = 11000,
            groupCooldownMs = 4000, actorLockMs = 1900 },
        CAREFUL_LAST_WARNING = { priority = 92, chance = 100, cooldownMs = 7000,
            groupCooldownMs = 2600, actorLockMs = 1900, interrupt = true },
        CAREFUL_HOSTILE = { priority = 96, chance = 100, cooldownMs = 12000,
            groupCooldownMs = 2400, actorLockMs = 1700, interrupt = true },

        SHOUT_FRIENDLY = { priority = 70, chance = 100, cooldownMs = 8000,
            groupCooldownMs = 4000, actorLockMs = 1600 },
        SHOUT_NEUTRAL = { priority = 70, chance = 100, cooldownMs = 8000,
            groupCooldownMs = 4000, actorLockMs = 1600 },
        SHOUT_CAREFUL = { priority = 86, chance = 100, cooldownMs = 7000,
            groupCooldownMs = 3000, actorLockMs = 1700, interrupt = true },
        SHOUT_HOSTILE = { priority = 88, chance = 100, cooldownMs = 7000,
            groupCooldownMs = 3000, actorLockMs = 1700, interrupt = true },
    }
    for id, specification in pairs(ladder) do
        if Catalog.events[id] == nil then
            specification.category = "combat"
            specification.priority = specification.priority or defaults.priority
            Catalog.events[id] = specification
        end
    end

    for style, lines in pairs(Styles.lines) do
        Catalog.styles[style] = Catalog.styles[style] or {}
        for event, entries in pairs(lines) do
            Catalog.styles[style][event] = entries
        end
    end

    for _, tone in ipairs({ "calm", "aggressive" }) do
        Catalog.styles[tone] = Catalog.styles[tone] or {}
        Catalog.styles[tone].CAREFUL_KEEP_BACK = Catalog.styles[tone].CAREFUL_KEEP_BACK
            or { "That's close enough.", "Keep your distance." }

        Catalog.styles[tone].CAREFUL_KEEP_BACK_FIGHTING = Catalog.styles[tone].CAREFUL_KEEP_BACK_FIGHTING
            or { "We are busy. Stay back.", "Not now. Keep your distance." }
        Catalog.styles[tone].CAREFUL_LAST_WARNING = Catalog.styles[tone].CAREFUL_LAST_WARNING
            or { "Last warning. Back away.", "One more step and we fire." }
        Catalog.styles[tone].CAREFUL_HOSTILE = Catalog.styles[tone].CAREFUL_HOSTILE
            or { "That's enough. Back off!", "That's it -- take {him}." }
        Catalog.styles[tone].SHOUT_FRIENDLY = Catalog.styles[tone].SHOUT_FRIENDLY
            or { "Over here! Come on in!", "We hear you, friend. Come over." }
        Catalog.styles[tone].SHOUT_NEUTRAL = Catalog.styles[tone].SHOUT_NEUTRAL
            or { "Keep it down out there.", "Quiet! You'll draw them." }
        Catalog.styles[tone].SHOUT_CAREFUL = Catalog.styles[tone].SHOUT_CAREFUL
            or { "Stay where you are. Don't come closer.", "We hear you. Keep back!" }
        Catalog.styles[tone].SHOUT_HOSTILE = Catalog.styles[tone].SHOUT_HOSTILE
            or { "{he}'s over there! Move!", "{he} called it. Take {him}." }
    end

end

ProjectALife.FactionVoiceInstall = function(Catalog)
    if type(Catalog) ~= "table" or Catalog.factionLookupInstalled then return end
    if type(Catalog.entries) ~= "function" then return end
    Catalog.factionLookupInstalled = true
    local original = Catalog.entries
    Catalog.entriesByTone = original
    Catalog.entries = function(profileId, value, styleId)
        local event = Catalog.resolveEvent(value)
        local requested = type(profileId) == "string" and string.lower(profileId) or ""
        local id = Catalog.profiles[requested] and requested
            or Catalog.resolveProfile(profileId, false)
        local profile = Catalog.profiles[id]
        if event == nil or profile == nil then return {} end
        local authored = profile.lines and profile.lines[event]
        if type(authored) == "table" and #authored > 0 then return original(profileId, value) end
        local style = type(styleId) == "string" and Catalog.styles[styleId] or nil
        local pool = style and style[event] or nil
        if type(pool) ~= "table" or #pool == 0 then return original(profileId, value) end
        local result = {}
        for _, entry in ipairs(pool) do
            if type(entry) == "string" then result[#result + 1] = { text = entry, weight = 1 }
            elseif type(entry) == "table" then result[#result + 1] = entry end
        end
        return result
    end
end

return Styles
