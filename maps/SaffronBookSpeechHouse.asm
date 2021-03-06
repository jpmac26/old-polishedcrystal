const_value set 2
	const SAFFRONBOOKSPEECHHOUSE_LASS
	const SAFFRONBOOKSPEECHHOUSE_BOOK

SaffronBookSpeechHouse_MapScriptHeader:
.MapTriggers:
	db 0

.MapCallbacks:
	db 0

SaffronBookSpeechHouseLassScript:
	jumptextfaceplayer SaffronBookSpeechHouseLassText

SaffronBookSpeechHouseBookScript:
	jumptext SaffronBookSpeechHouseBookText

SaffronBookSpeechHouseBookshelf1:
	jumpstd picturebookshelf

SaffronBookSpeechHouseBookshelf2:
	jumpstd difficultbookshelf

SaffronBookSpeechHouseLassText:
	text "I absolutely love"
	line "to read!"

	para "I borrowed a bunch"
	line "of books from the"

	para "university library"
	line "in Celadon."
	done

SaffronBookSpeechHouseBookText:
	text "It's a stack of"
	line "story books."

	para "The Princess and"
	line "the #mon,"

	para "Edward Scizor-"
	line "hands, Dr.Jekyll"
	cont "& Mr.Mime…"
	done

SaffronBookSpeechHouse_MapEventHeader:
	; filler
	db 0, 0

.Warps:
	db 2
	warp_def $7, $2, 18, SAFFRON_CITY
	warp_def $7, $3, 18, SAFFRON_CITY

.XYTriggers:
	db 0

.Signposts:
	db 2
	signpost 1, 5, SIGNPOST_READ, SaffronBookSpeechHouseBookshelf1
	signpost 1, 7, SIGNPOST_READ, SaffronBookSpeechHouseBookshelf2

.PersonEvents:
	db 2
	person_event SPRITE_LASS, 3, 2, SPRITEMOVEDATA_STANDING_RIGHT, 0, 0, -1, -1, (1 << 3) | PAL_OW_PURPLE, PERSONTYPE_SCRIPT, 0, SaffronBookSpeechHouseLassScript, -1
	person_event SPRITE_BOOK_UNOWN_R, 3, 3, SPRITEMOVEDATA_STANDING_DOWN, 0, 0, -1, -1, (1 << 3) | PAL_OW_BROWN, PERSONTYPE_SCRIPT, 0, SaffronBookSpeechHouseBookScript, -1
