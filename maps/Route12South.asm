const_value set 2
	const ROUTE12SOUTH_FISHER1
	const ROUTE12SOUTH_FISHER2
	const ROUTE12SOUTH_FISHER3
	const ROUTE12SOUTH_FISHER4
	const ROUTE12SOUTH_YOUNGSTER1
	const ROUTE12SOUTH_YOUNGSTER2
	const ROUTE12SOUTH_YOUNGSTER3
	const ROUTE12SOUTH_LASS
	const ROUTE12SOUTH_YOUNGSTER4
	const ROUTE12SOUTH_POKE_BALL1
	const ROUTE12SOUTH_POKE_BALL2
	const ROUTE12SOUTH_CUT_TREE1
	const ROUTE12SOUTH_CUT_TREE2

Route12South_MapScriptHeader:
.MapTriggers:
	db 0

.MapCallbacks:
	db 0

TrainerFisherMartin:
	trainer EVENT_BEAT_FISHER_MARTIN, FISHER, MARTIN, FisherMartinSeenText, FisherMartinBeatenText, 0, FisherMartinScript

FisherMartinScript:
	end_if_just_battled
	opentext
	writetext UnknownText_0x1a704c
	waitbutton
	closetext
	end

FisherMartinSeenText:
	text "Patience is the"
	line "key to both fish-"
	cont "ing and #mon."
	done

FisherMartinBeatenText:
	text "Gwaaah!"
	done

UnknownText_0x1a704c:
	text "I'm too impatient"
	line "for fishing…"
	done

TrainerFisherStephen:
	trainer EVENT_BEAT_FISHER_STEPHEN, FISHER, STEPHEN, FisherStephenSeenText, FisherStephenBeatenText, 0, FisherStephenScript

FisherStephenScript:
	end_if_just_battled
	opentext
	writetext UnknownText_0x1a70d4
	waitbutton
	closetext
	end

FisherStephenSeenText:
	text "I feel so content,"
	line "fishing while lis-"
	cont "tening to some"
	cont "tunes on my radio."
	done

FisherStephenBeatenText:
	text "My stupid radio"
	line "distracted me!"
	done

UnknownText_0x1a70d4:
	text "Have you checked"
	line "out Kanto's radio"

	para "programs? We get a"
	line "good variety here."
	done

TrainerFisherBarney:
	trainer EVENT_BEAT_FISHER_BARNEY, FISHER, BARNEY, FisherBarneySeenText, FisherBarneyBeatenText, 0, FisherBarneyScript

FisherBarneyScript:
	end_if_just_battled
	opentext
	writetext UnknownText_0x1a716d
	waitbutton
	closetext
	end

FisherBarneySeenText:
	text "What's most impor-"
	line "tant in our every-"
	cont "day lives?"
	done

FisherBarneyBeatenText:
	text "The answer is"
	line "coming up next!"
	done

UnknownText_0x1a716d:
	text "I think electric-"
	line "ity is the most"

	para "important thing in"
	line "our daily lives."

	para "If it weren't,"
	line "people wouldn't"

	para "have made such a"
	line "fuss when the"

	para "Power Plant went"
	line "out of commission."
	done

TrainerFisherKyler:
	trainer EVENT_BEAT_FISHER_KYLER, FISHER, KYLER, .SeenText, .BeatenText, 0, .Script

.Script:
	end_if_just_battled
	opentext
	writetext .AfterText
	waitbutton
	closetext
	end

.SeenText:
	text "#mon battles"
	line "lure people in!"
	done

.BeatenText:
	text "My #mon bucket"
	line "is empty!"
	done

.AfterText:
	text "Really? Rather"
	line "than always catch-"
	cont "ing new #mon,"

	para "it's good to train"
	line "them?"
	done

TrainerBird_keeperJustin:
	trainer EVENT_BEAT_BIRD_KEEPER_JUSTIN, BIRD_KEEPER, BIRD_KEEPER_JUSTIN, .SeenText, .BeatenText, 0, .Script

.Script:
	end_if_just_battled
	opentext
	writetext .AfterText
	waitbutton
	closetext
	end

.SeenText:
	text "Huh? The wind has"
	line "changed direction!"
	done

.BeatenText:
	text "Phew…"
	done

.AfterText:
	text "Since the wind has"
	line "changed, I'll lay"
	cont "low…"
	done

TrainerBird_keeperGail:
	trainer EVENT_BEAT_BIRD_KEEPER_GAIL, BIRD_KEEPER, GAIL, .SeenText, .BeatenText, 0, .Script

.Script:
	end_if_just_battled
	opentext
	writetext .AfterText
	waitbutton
	closetext
	end

.SeenText:
	text "BASABASABASA-"
	line "BASABASA!"
	done

.BeatenText:
	text "Pyopyopyopyo…"
	done

.AfterText:
	text "Chuun-Chuun?"
	line "Chunchun!"
	done

TrainerCoupleVicandtara1:
	trainer EVENT_BEAT_COUPLE_VIC_AND_TARA, COUPLE, VICANDTARA1, .SeenText, .BeatenText, 0, .Script

.Script:
	end_if_just_battled
	opentext
	writetext .AfterText
	waitbutton
	closetext
	end

.SeenText:
	text "Vic: All right!"
	line "I'll be able to"
	cont "show off for Tara!"
	done

.BeatenText:
	text "Vic: Oh no, my"
	line "plans!"
	done

.AfterText:
	text "Vic: Tara already"
	line "saw me humiliated…"
	done

TrainerCoupleVicandtara2:
	trainer EVENT_BEAT_COUPLE_VIC_AND_TARA, COUPLE, VICANDTARA2, .SeenText, .BeatenText, 0, .Script

.Script:
	end_if_just_battled
	opentext
	writetext .AfterText
	waitbutton
	closetext
	end

.SeenText:
	text "Tara: I love to"
	line "look at my boy-"
	cont "friend's face while"
	cont "he's battling!"
	done

.BeatenText:
	text "Tara: Oh no,"
	line "oh no…"
	done

.AfterText:
	text "Tara: Even though"
	line "my boyfriend lost,"
	cont "he's still wonder-"
	cont "ful."
	done

Route12CutTree:
	jumpstd cuttree

Route12Sign:
	jumptext Route12SignText

Route12Calcium:
	itemball CALCIUM

Route12Nugget:
	itemball NUGGET

Route12HiddenElixer:
	dwb EVENT_ROUTE_12_HIDDEN_ELIXER, ELIXER

Route12SignText:
	text "Route 12"

	para "North to Lavender"
	line "Town"
	done

Route12South_MapEventHeader:
	; filler
	db 0, 0

.Warps:
	db 4
	warp_def $39, $b, 1, ROUTE_12_SUPER_ROD_HOUSE
	warp_def $2a, $0, 3, ROUTE_11_GATE
	warp_def $2b, $0, 4, ROUTE_11_GATE
	warp_def $1, $a, 3, ROUTE_12_GATE

.XYTriggers:
	db 0

.Signposts:
	db 2
	signpost 43, 11, SIGNPOST_READ, Route12Sign
	signpost 15, 14, SIGNPOST_ITEM, Route12HiddenElixer

.PersonEvents:
	db 13
	person_event SPRITE_FISHER, 7, 7, SPRITEMOVEDATA_SPINRANDOM_FAST, 0, 0, -1, -1, (1 << 3) | PAL_OW_GREEN, PERSONTYPE_TRAINER, 1, TrainerFisherMartin, -1
	person_event SPRITE_FISHER, 33, 14, SPRITEMOVEDATA_STANDING_DOWN, 0, 0, -1, -1, (1 << 3) | PAL_OW_GREEN, PERSONTYPE_TRAINER, 1, TrainerFisherStephen, -1
	person_event SPRITE_FISHER, 63, 12, SPRITEMOVEDATA_STANDING_LEFT, 0, 0, -1, -1, (1 << 3) | PAL_OW_GREEN, PERSONTYPE_TRAINER, 5, TrainerFisherBarney, -1
	person_event SPRITE_FISHER, 74, 10, SPRITEMOVEDATA_STANDING_LEFT, 0, 0, -1, -1, (1 << 3) | PAL_OW_GREEN, PERSONTYPE_TRAINER, 1, TrainerFisherKyler, -1
	person_event SPRITE_YOUNGSTER, 24, 10, SPRITEMOVEDATA_SPINRANDOM_SLOW, 0, 0, -1, -1, (1 << 3) | PAL_OW_BLUE, PERSONTYPE_TRAINER, 1, TrainerBird_keeperJustin, -1
	person_event SPRITE_YOUNGSTER, 57, 7, SPRITEMOVEDATA_SPINCLOCKWISE, 0, 0, -1, -1, (1 << 3) | PAL_OW_BLUE, PERSONTYPE_TRAINER, 2, TrainerBird_keeperGail, -1
	person_event SPRITE_YOUNGSTER, 39, 10, SPRITEMOVEDATA_STANDING_RIGHT, 0, 0, -1, -1, (1 << 3) | PAL_OW_BLUE, PERSONTYPE_TRAINER, 1, TrainerCoupleVicandtara1, -1
	person_event SPRITE_LASS, 38, 10, SPRITEMOVEDATA_STANDING_RIGHT, 0, 0, -1, -1, (1 << 3) | PAL_OW_BLUE, PERSONTYPE_TRAINER, 1, TrainerCoupleVicandtara2, -1
	person_event SPRITE_YOUNGSTER, 89, 14, SPRITEMOVEDATA_STANDING_DOWN, 0, 0, -1, -1, (1 << 3) | PAL_OW_BLUE, PERSONTYPE_SCRIPT, 0, ObjectEvent, -1
	person_event SPRITE_BALL_CUT_FRUIT, 68, 5, SPRITEMOVEDATA_STANDING_DOWN, 0, 0, -1, -1, (1 << 3) | PAL_OW_RED, PERSONTYPE_ITEMBALL, 0, Route12Calcium, EVENT_ROUTE_12_CALCIUM
	person_event SPRITE_BALL_CUT_FRUIT, 82, 5, SPRITEMOVEDATA_STANDING_DOWN, 0, 0, -1, -1, (1 << 3) | PAL_OW_RED, PERSONTYPE_ITEMBALL, 0, Route12Nugget, EVENT_ROUTE_12_NUGGET
	person_event SPRITE_BALL_CUT_FRUIT, 71, 6, SPRITEMOVEDATA_CUTTABLE_TREE, 0, 0, -1, -1, 0, PERSONTYPE_SCRIPT, 0, Route12CutTree, EVENT_ROUTE_12_CUT_TREE_1
	person_event SPRITE_BALL_CUT_FRUIT, 79, 9, SPRITEMOVEDATA_CUTTABLE_TREE, 0, 0, -1, -1, 0, PERSONTYPE_SCRIPT, 0, Route12CutTree, EVENT_ROUTE_12_CUT_TREE_2
