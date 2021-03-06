BattleCommand_Attract: ; 377ce
; attract
	ld a, [AttackMissed]
	and a
	jr nz, .failed
	call CheckOppositeGender
	jr c, .failed
	call CheckHiddenOpponent
	jr nz, .failed
	ld a, BATTLE_VARS_SUBSTATUS1_OPP
	call GetBattleVarAddr
	bit SUBSTATUS_IN_LOVE, [hl]
	jr nz, .failed
	call GetOpponentAbilityAfterMoldBreaker
	cp OBLIVIOUS
	jr nz, .no_ability_protection
	farcall ShowEnemyAbilityActivation
	ld hl, DoesntAffectText
	jp StdBattleTextBox

.no_ability_protection
	; maybe this was called by cute charm
	call ShowPotentialAbilityActivation
	set SUBSTATUS_IN_LOVE, [hl]
	call AnimateCurrentMove

; 'fell in love!'
	ld hl, FellInLoveText
	call StdBattleTextBox
	farcall RunEnemyStatusHealAbilities
	ret

.failed
	jp FailAttract
; 377f5


CheckOppositeGender: ; 377f5
	ld a, MON_SPECIES
	call BattlePartyAttr
	ld a, [hl]
	ld [CurPartySpecies], a

	ld a, [CurBattleMon]
	ld [CurPartyMon], a
	xor a
	ld [MonType], a

	farcall GetGender
	jr c, .genderless_samegender

	ld b, 1
	jr nz, .got_gender
	dec b

.got_gender
	push bc
	ld a, [TempEnemyMonSpecies]
	ld [CurPartySpecies], a
	ld hl, EnemyMonGender
	ld a, [EnemySubStatus2]
	bit SUBSTATUS_TRANSFORMED, a
	jr z, .not_transformed
	ld hl, wEnemyBackupGender
.not_transformed
	ld a, [hl]
	ld [TempMonGender], a
	ld a, 3
	ld [MonType], a
	farcall GetGender
	pop bc
	jr c, .genderless_samegender

	ld a, 1
	jr nz, .got_enemy_gender
	dec a

.got_enemy_gender
	xor b
	jr z, .genderless_samegender

	and a
	ret

.genderless_samegender
	scf
	ret
; 3784b
