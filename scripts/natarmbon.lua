--
-- Please see the LICENSE.md file included with this distribution for attribution and copyright information.
--
local function getDefenseValue_kel(rAttacker, rDefender, rRoll) -- luacheck: ignore
	-- VALIDATE
	if not rDefender or not rRoll then return nil, 0, 0, 0; end

	local sAttack = rRoll.sDesc;

	-- DETERMINE ATTACK TYPE AND DEFENSE
	local sAttackType = 'M';
	if rRoll.sType == 'attack' then sAttackType = string.match(sAttack, '%[ATTACK.*%((%w+)%)%]'); end
	local bOpportunity = string.match(sAttack, '%[OPPORTUNITY%]');
	local bTouch = true;
	if rRoll.sType == 'attack' then bTouch = string.match(sAttack, '%[TOUCH%]'); end
	-- KEL Putting this definition already here, was for implementing ghost armor but maybe I do not need this anymore
	local bIncorporealAttack = string.match(sAttack, '%[INCORPOREAL%]');
	-- if string.match(sAttack, "%[INCORPOREAL%]") then
	-- bIncorporealAttack = true;
	-- end
	-- KEL check for uncanny dodge here not needed, but maybe a security check?
	local bFlatFooted = string.match(sAttack, '%[FF%]');
	local nCover = tonumber(string.match(sAttack, '%[COVER %-(%d)%]')) or 0;
	local bConceal = string.match(sAttack, '%[CONCEAL%]');
	local bTotalConceal = string.match(sAttack, '%[TOTAL CONC%]');
	local bAttackerBlinded = string.match(sAttack, '%[BLINDED%]');

	-- Determine the defense database node name
	local nDefense = 10;
	local nFlatFootedMod = 0;
	local nTouchMod = 0;
	local sDefenseStat = 'dexterity';
	local sDefenseStat2 = '';
	local sDefenseStat3 = '';
	if rRoll.sType == 'grapple' then sDefenseStat3 = 'strength'; end

	local sDefenderNodeType, nodeDefender = ActorManager.getTypeAndNode(rDefender);
	if not nodeDefender then return nil, 0, 0, 0; end

	if sDefenderNodeType == 'pc' then
		if rRoll.sType == 'attack' then
			nDefense = DB.getValue(nodeDefender, 'ac.totals.general', 10);
			nFlatFootedMod = nDefense - DB.getValue(nodeDefender, 'ac.totals.flatfooted', 10);
			nTouchMod = nDefense - DB.getValue(nodeDefender, 'ac.totals.touch', 10);
		else
			nDefense = DB.getValue(nodeDefender, 'ac.totals.cmd', 10);
			nFlatFootedMod = DB.getValue(nodeDefender, 'ac.totals.general', 10) - DB.getValue(nodeDefender, 'ac.totals.flatfooted', 10);
		end
		sDefenseStat = DB.getValue(nodeDefender, 'ac.sources.ability', '');
		if sDefenseStat == '' then sDefenseStat = 'dexterity'; end
		sDefenseStat2 = DB.getValue(nodeDefender, 'ac.sources.ability2', '');
		if rRoll.sType == 'grapple' then
			sDefenseStat3 = DB.getValue(nodeDefender, 'ac.sources.cmdability', '');
			if sDefenseStat3 == '' then sDefenseStat3 = 'strength'; end
		end
	elseif sDefenderNodeType == 'ct' then
		if rRoll.sType == 'attack' then
			nDefense = DB.getValue(nodeDefender, 'ac_final', 10);
			nFlatFootedMod = nDefense - DB.getValue(nodeDefender, 'ac_flatfooted', 10);
			nTouchMod = nDefense - DB.getValue(nodeDefender, 'ac_touch', 10);
		else
			nDefense = DB.getValue(nodeDefender, 'cmd', 10);
			nFlatFootedMod = DB.getValue(nodeDefender, 'ac_final', 10) - DB.getValue(nodeDefender, 'ac_flatfooted', 10);
		end
	elseif sDefenderNodeType == 'npc' then
		if rRoll.sType == 'attack' then
			local sAC = DB.getValue(nodeDefender, 'ac', '');
			nDefense = tonumber(string.match(sAC, '^%s*(%d+)')) or 10;

			local sFlatFootedAC = string.match(sAC, 'flat-footed (%d+)');
			if sFlatFootedAC then
				nFlatFootedMod = nDefense - tonumber(sFlatFootedAC);
			else
				nFlatFootedMod = ActorManager35E.getAbilityBonus(rDefender, sDefenseStat);
			end

			local sTouchAC = string.match(sAC, 'touch (%d+)');
			if sTouchAC then nTouchMod = nDefense - tonumber(sTouchAC); end
		else
			local sBABGrp = DB.getValue(nodeDefender, 'babgrp', '');
			local sMatch = string.match(sBABGrp, 'CMD ([+-]?[0-9]+)');
			if sMatch then
				nDefense = tonumber(sMatch) or 10;
			else
				nDefense = 10;
			end

			local sAC = DB.getValue(nodeDefender, 'ac', '');
			local nAC = tonumber(string.match(sAC, '^%s*(%d+)')) or 10;

			local sFlatFootedAC = string.match(sAC, 'flat-footed (%d+)');
			if sFlatFootedAC then
				nFlatFootedMod = nAC - tonumber(sFlatFootedAC);
			else
				nFlatFootedMod = ActorManager35E.getAbilityBonus(rDefender, sDefenseStat);
			end
		end
	end

	nDefenseStatMod = ActorManager35E.getAbilityBonus(rDefender, sDefenseStat) + ActorManager35E.getAbilityBonus(rDefender, sDefenseStat2);

	-- MAKE SURE FLAT-FOOTED AND TOUCH ADJUSTMENTS ARE POSITIVE
	if nTouchMod < 0 then nTouchMod = 0; end
	if nFlatFootedMod < 0 then nFlatFootedMod = 0; end

	-- APPLY FLAT-FOOTED AND TOUCH ADJUSTMENTS
	if bTouch then nDefense = nDefense - nTouchMod; end
	if bFlatFooted then nDefense = nDefense - nFlatFootedMod; end

	-- EFFECT MODIFIERS
	local nDefenseEffectMod = 0;
	-- KEL ACCC stuff
	local nAdditionalDefenseForCC = 0;
	local nMissChance = 0;
	if ActorManager.hasCT(rDefender) then
		-- SETUP
		local bCombatAdvantage = false;
		local bZeroAbility = false;
		local nBonusAC = 0;
		-- KEL ACCC
		local nBonusACCC = 0;
		local nBonusStat = 0;
		local nBonusSituational = 0;

		local bPFMode = DataCommon.isPFRPG();

		-- BUILD ATTACK FILTER
		local aAttackFilter = {};
		if sAttackType == 'M' then
			table.insert(aAttackFilter, 'melee');
		elseif sAttackType == 'R' then
			table.insert(aAttackFilter, 'ranged');
		end
		if bOpportunity then table.insert(aAttackFilter, 'opportunity'); end

		-- CHECK IF COMBAT ADVANTAGE ALREADY SET BY ATTACKER EFFECT
		if sAttack:match('%[CA%]') then bCombatAdvantage = true; end

		-- GET DEFENDER SITUATIONAL MODIFIERS - GENERAL
		-- KEL adding uncanny dodge, blind-fight and ethereal; also improving performance a little bit
		if EffectManager35E.hasEffect(rAttacker, 'Ethereal', rDefender, true, false, rRoll.tags) then
			nBonusSituational = nBonusSituational - 2;
			if not ActorManager35E.hasSpecialAbility(rDefender, 'Uncanny Dodge', false, false, true) then bCombatAdvantage = true; end
		elseif EffectManager35E.hasEffect(rAttacker, 'Invisible', rDefender, true, false, rRoll.tags) then
			local bBlindFight = ActorManager35E.hasSpecialAbility(rDefender, 'Blind-Fight', true, false, false);
			if sAttackType == 'R' or not bBlindFight then
				nBonusSituational = nBonusSituational - 2;
				if not ActorManager35E.hasSpecialAbility(rDefender, 'Uncanny Dodge', false, false, true) then bCombatAdvantage = true; end
			end
		end
		if EffectManager35E.hasEffect(rAttacker, 'CA', rDefender, true, false, rRoll.tags) then
			bCombatAdvantage = true;
		elseif EffectManager35E.hasEffect(rDefender, 'GRANTCA', rAttacker, false, false, rRoll.tags) then
			bCombatAdvantage = true;
		end
		-- END
		if EffectManager35E.hasEffect(rDefender, 'Blinded', nil, false, false, rRoll.tags) then
			nBonusSituational = nBonusSituational - 2;
			bCombatAdvantage = true;
		end
		if EffectManager35E.hasEffect(rDefender, 'Cowering', nil, false, false, rRoll.tags) or
						EffectManager35E.hasEffect(rDefender, 'Rebuked', nil, false, false, rRoll.tags) then
			nBonusSituational = nBonusSituational - 2;
			bCombatAdvantage = true;
		end
		if EffectManager35E.hasEffect(rDefender, 'Slowed', nil, false, false, rRoll.tags) then nBonusSituational = nBonusSituational - 1; end
		-- KEL adding uncanny dodge
		if ((EffectManager35E.hasEffect(rDefender, 'Flat-footed', nil, false, false, rRoll.tags) or
						EffectManager35E.hasEffect(rDefender, 'Flatfooted', nil, false, false, rRoll.tags)) and
						not ActorManager35E.hasSpecialAbility(rDefender, 'Uncanny Dodge', false, false, true)) or
						EffectManager35E.hasEffect(rDefender, 'Climbing', nil, false, false, rRoll.tags) or
						EffectManager35E.hasEffect(rDefender, 'Running', nil, false, false, rRoll.tags) then bCombatAdvantage = true; end
		if EffectManager35E.hasEffect(rDefender, 'Pinned', nil, false, false, rRoll.tags) then
			bCombatAdvantage = true;
			if bPFMode then
				nBonusSituational = nBonusSituational - 4;
			else
				if not EffectManager35E.hasEffect(rAttacker, 'Grappled', nil, false, false, rRoll.tags) then
					nBonusSituational = nBonusSituational - 4;
				end
			end
		elseif not bPFMode and EffectManager35E.hasEffect(rDefender, 'Grappled', nil, false, false, rRoll.tags) then
			if not EffectManager35E.hasEffect(rAttacker, 'Grappled', nil, false, false, rRoll.tags) then bCombatAdvantage = true; end
		end
		if EffectManager35E.hasEffect(rDefender, 'Helpless', nil, false, false, rRoll.tags) or
						EffectManager35E.hasEffect(rDefender, 'Paralyzed', nil, false, false, rRoll.tags) or
						EffectManager35E.hasEffect(rDefender, 'Petrified', nil, false, false, rRoll.tags) or
						EffectManager35E.hasEffect(rDefender, 'Unconscious', nil, false, false, rRoll.tags) then
			if sAttackType == 'M' then nBonusSituational = nBonusSituational - 4; end
			bZeroAbility = true;
		end
		if EffectManager35E.hasEffect(rDefender, 'Kneeling', nil, false, false, rRoll.tags) or
						EffectManager35E.hasEffect(rDefender, 'Sitting', nil, false, false, rRoll.tags) then
			if sAttackType == 'M' then
				nBonusSituational = nBonusSituational - 2;
			elseif sAttackType == 'R' then
				nBonusSituational = nBonusSituational + 2;
			end
		elseif EffectManager35E.hasEffect(rDefender, 'Prone', nil, false, false, rRoll.tags) then
			if sAttackType == 'M' then
				nBonusSituational = nBonusSituational - 4;
			elseif sAttackType == 'R' then
				nBonusSituational = nBonusSituational + 4;
			end
		end
		if EffectManager35E.hasEffect(rDefender, 'Squeezing', nil, false, false, rRoll.tags) then nBonusSituational = nBonusSituational - 4; end
		if EffectManager35E.hasEffect(rDefender, 'Stunned', nil, false, false, rRoll.tags) then
			nBonusSituational = nBonusSituational - 2;
			if rRoll.sType == 'grapple' then nBonusSituational = nBonusSituational - 4; end
			bCombatAdvantage = true;
		end
		-- KEL Ethereal
		if EffectManager35E.hasEffect(rDefender, 'Invisible', rAttacker, false, false, rRoll.tags) or
						EffectManager35E.hasEffect(rDefender, 'Ethereal', rAttacker, false, false, rRoll.tags) then bTotalConceal = true; end
		-- END
		-- DETERMINE EXISTING AC MODIFIER TYPES
		local aExistingBonusByType = ActorManager35E.getArmorComps(rDefender);

		-- GET DEFENDER ALL DEFENSE MODIFIERS
		local aIgnoreEffects = {};
		if bTouch then
			table.insert(aIgnoreEffects, 'armor');
			table.insert(aIgnoreEffects, 'shield');
			table.insert(aIgnoreEffects, 'natural');
			table.insert(aIgnoreEffects, 'naturalsize');
			table.insert(aIgnoreEffects, 'armorenhancement');
			table.insert(aIgnoreEffects, 'shieldenhancement');
			table.insert(aIgnoreEffects, 'naturalenhancement');
		end
		if bFlatFooted or bCombatAdvantage then table.insert(aIgnoreEffects, 'dodge'); end
		if rRoll.sType == 'grapple' then table.insert(aIgnoreEffects, 'size'); end
		local aACEffects = EffectManager35E.getEffectsBonusByType(rDefender, { 'AC' }, true, aAttackFilter, rAttacker, false, rRoll.tags);
		for k, v in pairs(aACEffects) do
			if not StringManager.contains(aIgnoreEffects, k) then
				local sBonusType = DataCommon.actypes[k];
				if sBonusType then
					-- Dodge bonuses stack (by rules)
					if sBonusType == 'dodge' then
						nBonusAC = nBonusAC + v.mod;
						-- elseif sBonusType == "ghost" then; KEL Deprecated at the moment
						-- nBonusAC = nBonusAC + v.mod;
						-- Size bonuses stack (by usage expectation)
					elseif sBonusType == 'size' then
						nBonusAC = nBonusAC + v.mod;
					elseif aExistingBonusByType[sBonusType] then
						if v.mod < 0 then
							nBonusAC = nBonusAC + v.mod;
						elseif v.mod > aExistingBonusByType[sBonusType] then
							nBonusAC = nBonusAC + v.mod - aExistingBonusByType[sBonusType];
							-- KEL change aExistingBonusByType for the ACCC stacking check
							aExistingBonusByType[sBonusType] = v.mod;
						end
					else
						nBonusAC = nBonusAC + v.mod;
						-- KEL Create aExistingBonusByType for ACCC stacking check
						aExistingBonusByType[sBonusType] = v.mod;
					end
				else
					nBonusAC = nBonusAC + v.mod;
				end
			end
		end
		-- KEL rmilmine ACCC requested, beware stacking stuff
		local aACCCEffects = EffectManager35E.getEffectsBonusByType(rDefender, { 'ACCC' }, true, aAttackFilter, rAttacker, false, rRoll.tags);
		for k, v in pairs(aACCCEffects) do
			if not StringManager.contains(aIgnoreEffects, k) then
				local sBonusType = DataCommon.actypes[k];
				if sBonusType then
					-- Dodge bonuses stack (by rules)
					if sBonusType == 'dodge' then
						nBonusACCC = nBonusACCC + v.mod;
						-- Size bonuses stack (by usage expectation)
					elseif sBonusType == 'size' then
						nBonusACCC = nBonusACCC + v.mod;
					elseif aExistingBonusByType[sBonusType] then
						if v.mod < 0 then
							nBonusACCC = nBonusACCC + v.mod;
						elseif v.mod > aExistingBonusByType[sBonusType] then
							nBonusACCC = nBonusACCC + v.mod - aExistingBonusByType[sBonusType];
							aExistingBonusByType[sBonusType] = v.mod;
						end
					else
						nBonusACCC = nBonusACCC + v.mod;
						aExistingBonusByType[sBonusType] = v.mod;
					end
				else
					nBonusACCC = nBonusACCC + v.mod;
				end
			end
		end
		-- END
		if rRoll.sType == 'grapple' then
			local nPFMod, nPFCount = EffectManager35E.getEffectsBonus(rDefender, { 'CMD' }, true, aAttackFilter, rAttacker, false, rRoll.tags);
			if nPFCount > 0 then nBonusAC = nBonusAC + nPFMod; end
		end

		-- GET DEFENDER DEFENSE STAT MODIFIERS
		local nBonusStat = 0;
		-- Kel Also here tags, everywhere :D
		local nBonusStat1 = ActorManager35E.getAbilityEffectsBonus(rDefender, sDefenseStat, rRoll.tags);
		if (sDefenderNodeType == 'pc') and (nBonusStat1 > 0) then
			if DB.getValue(nodeDefender, 'encumbrance.armormaxstatbonusactive', 0) == 1 then
				local nCurrentStatBonus = ActorManager35E.getAbilityBonus(rDefender, sDefenseStat);
				local nMaxStatBonus = math.max(DB.getValue(nodeDefender, 'encumbrance.armormaxstatbonus', 0), 0);
				local nMaxEffectStatModBonus = math.max(nMaxStatBonus - nCurrentStatBonus, 0);
				if nBonusStat1 > nMaxEffectStatModBonus then nBonusStat1 = nMaxEffectStatModBonus; end
			end
		end
		if not bFlatFooted and not bCombatAdvantage and sDefenseStat == 'dexterity' then nFlatFootedMod = nFlatFootedMod + nBonusStat1; end
		nBonusStat = nBonusStat + nBonusStat1;
		local nBonusStat2 = ActorManager35E.getAbilityEffectsBonus(rDefender, sDefenseStat2, rRoll.tags);
		if not bFlatFooted and not bCombatAdvantage and sDefenseStat2 == 'dexterity' then nFlatFootedMod = nFlatFootedMod + nBonusStat2; end
		nBonusStat = nBonusStat + nBonusStat2;
		local nBonusStat3 = ActorManager35E.getAbilityEffectsBonus(rDefender, sDefenseStat3, rRoll.tags);
		if not bFlatFooted and not bCombatAdvantage and sDefenseStat3 == 'dexterity' then nFlatFootedMod = nFlatFootedMod + nBonusStat3; end
		nBonusStat = nBonusStat + nBonusStat3;
		if bFlatFooted or bCombatAdvantage then
			-- IF NEGATIVE AND AC STAT BONUSES, THEN ONLY APPLY THE AMOUNT THAT EXCEEDS AC STAT BONUSES
			if nBonusStat < 0 then
				if nDefenseStatMod > 0 then nBonusStat = math.min(nDefenseStatMod + nBonusStat, 0); end

				-- IF POSITIVE AND AC STAT PENALTIES, THEN ONLY APPLY UP TO AC STAT PENALTIES
			else
				if nDefenseStatMod < 0 then
					nBonusStat = math.min(nBonusStat, -nDefenseStatMod);
				else
					nBonusStat = 0;
				end
			end
		end

		-- HANDLE NEGATIVE LEVELS
		if rRoll.sType == 'grapple' then
			local nNegLevelMod, nNegLevelCount = EffectManager35E.getEffectsBonus(rDefender, { 'NLVL' }, true, nil, nil, false, rRoll.tags);
			if nNegLevelCount > 0 then nBonusSituational = nBonusSituational - nNegLevelMod; end
		end

		-- HANDLE DEXTERITY MODIFIER REMOVAL
		if bZeroAbility then
			if bFlatFooted then
				nBonusSituational = nBonusSituational - 5;
			else
				nBonusSituational = nBonusSituational - nFlatFootedMod - 5;
			end
		elseif bCombatAdvantage and not bFlatFooted then
			nBonusSituational = nBonusSituational - nFlatFootedMod;
		end

		-- GET DEFENDER SITUATIONAL MODIFIERS - COVER
		if nCover < 8 then
			local aCover = EffectManager35E.getEffectsByType(rDefender, 'SCOVER', aAttackFilter, rAttacker, false, rRoll.tags);
			if #aCover > 0 or EffectManager35E.hasEffect(rDefender, 'SCOVER', rAttacker, false, false, rRoll.tags) then
				nBonusSituational = nBonusSituational + 8 - nCover;
			elseif nCover < 4 then
				aCover = EffectManager35E.getEffectsByType(rDefender, 'COVER', aAttackFilter, rAttacker, false, rRoll.tags);
				if #aCover > 0 or EffectManager35E.hasEffect(rDefender, 'COVER', rAttacker, false, false, rRoll.tags) then
					nBonusSituational = nBonusSituational + 4 - nCover;
				elseif nCover < 2 then
					aCover = EffectManager35E.getEffectsByType(rDefender, 'PCOVER', aAttackFilter, rAttacker, false, rRoll.tags);
					if #aCover > 0 or EffectManager35E.hasEffect(rDefender, 'PCOVER', rAttacker, false, false, rRoll.tags) then
						nBonusSituational = nBonusSituational + 2 - nCover;
					end
				end
			end
		end

		-- GET DEFENDER SITUATIONAL MODIFIERS - CONCEALMENT
		-- KEL Variable concealment; do not use getEffectsBonus because we do not want that untyped boni are stacking
		local aVConcealEffect, aVConcealCount = EffectManager35E.getEffectsBonusByType(
						                                        rDefender, 'VCONC', true, aAttackFilter, rAttacker, false, rRoll.tags
		                                        );

		if aVConcealCount > 0 then for _, v in pairs(aVConcealEffect) do nMissChance = math.max(v.mod, nMissChance); end end
		-- END variable concealment but check that CONC and TCONC etc. do not overwrite VCONC and only maximum value is taken
		if not (nMissChance >= 50) then
			local aConceal = EffectManager35E.getEffectsByType(rDefender, 'TCONC', aAttackFilter, rAttacker, false, rRoll.tags);
			if #aConceal > 0 or EffectManager35E.hasEffect(rDefender, 'TCONC', rAttacker, false, false, rRoll.tags) or bTotalConceal or
							bAttackerBlinded then
				nMissChance = 50;
			elseif not (nMissChance >= 20) then
				aConceal = EffectManager35E.getEffectsByType(rDefender, 'CONC', aAttackFilter, rAttacker, false, rRoll.tags);
				if #aConceal > 0 or EffectManager35E.hasEffect(rDefender, 'CONC', rAttacker, false, false, rRoll.tags) or bConceal then
					nMissChance = 20;
				end
			end
		end

		-- CHECK INCORPOREALITY
		if not bPFMode and (nMissChance < 50) then
			local bIncorporealDefender = EffectManager35E.hasEffect(rDefender, 'Incorporeal', rAttacker, false, false, rRoll.tags);
			local bGhostTouchAttacker = EffectManager35E.hasEffect(rAttacker, 'ghost touch', rDefender, false, false, rRoll.tags);

			if bIncorporealDefender and not bGhostTouchAttacker and not bIncorporealAttack then nMissChance = 50; end
		end

		-- ADD IN EFFECT MODIFIERS
		nDefenseEffectMod = nBonusAC + nBonusStat + nBonusSituational;
		-- KEL ACCC
		nAdditionalDefenseForCC = nBonusACCC;

		-- NO DEFENDER SPECIFIED, SO JUST LOOK AT THE ATTACK ROLL MODIFIERS, here no math.max needed but to be sure...
	else
		if bTotalConceal or bAttackerBlinded then
			nMissChance = math.max(50, nMissChance);
		elseif bConceal then
			nMissChance = math.max(20, nMissChance);
		end
		-- KEL the following is useless :)
		local bPFMode = DataCommon.isPFRPG();
		if bIncorporealAttack and not bPFMode then nMissChance = math.max(50, nMissChance); end
	end

	-- Return the final defense value
	-- KEL ACCC output
	return nDefense, 0, nDefenseEffectMod, nMissChance, nAdditionalDefenseForCC;
end

local function getDefenseValue_new(rAttacker, rDefender, rRoll)
	-- VALIDATE
	if not rDefender or not rRoll then return nil, 0, 0, 0; end

	local sAttack = rRoll.sDesc;

	-- DETERMINE ATTACK TYPE AND DEFENSE
	local sAttackType = 'M';
	if rRoll.sType == 'attack' then sAttackType = string.match(sAttack, '%[ATTACK.*%((%w+)%)%]'); end
	local bOpportunity = string.match(sAttack, '%[OPPORTUNITY%]');
	local bTouch = true;
	if rRoll.sType == 'attack' then bTouch = string.match(sAttack, '%[TOUCH%]'); end
	local bFlatFooted = string.match(sAttack, '%[FF%]');
	local nCover = tonumber(string.match(sAttack, '%[COVER %-(%d)%]')) or 0;
	local bConceal = string.match(sAttack, '%[CONCEAL%]');
	local bTotalConceal = string.match(sAttack, '%[TOTAL CONC%]');
	local bAttackerBlinded = string.match(sAttack, '%[BLINDED%]');

	-- Determine the defense database node name
	local nDefense = 10;
	local nFlatFootedMod = 0;
	local nTouchMod = 0;
	local sDefenseStat = 'dexterity';
	local sDefenseStat2 = '';
	local sDefenseStat3 = '';
	if rRoll.sType == 'grapple' then sDefenseStat3 = 'strength'; end

	local sDefenderNodeType, nodeDefender = ActorManager.getTypeAndNode(rDefender);
	if not nodeDefender then return nil, 0, 0, 0; end

	if sDefenderNodeType == 'pc' then
		if rRoll.sType == 'attack' then
			nDefense = DB.getValue(nodeDefender, 'ac.totals.general', 10);
			nFlatFootedMod = nDefense - DB.getValue(nodeDefender, 'ac.totals.flatfooted', 10);
			nTouchMod = nDefense - DB.getValue(nodeDefender, 'ac.totals.touch', 10);
		else
			nDefense = DB.getValue(nodeDefender, 'ac.totals.cmd', 10);
			nFlatFootedMod = DB.getValue(nodeDefender, 'ac.totals.general', 10) - DB.getValue(nodeDefender, 'ac.totals.flatfooted', 10);
		end
		sDefenseStat = DB.getValue(nodeDefender, 'ac.sources.ability', '');
		if sDefenseStat == '' then sDefenseStat = 'dexterity'; end
		sDefenseStat2 = DB.getValue(nodeDefender, 'ac.sources.ability2', '');
		if rRoll.sType == 'grapple' then
			sDefenseStat3 = DB.getValue(nodeDefender, 'ac.sources.cmdability', '');
			if sDefenseStat3 == '' then sDefenseStat3 = 'strength'; end
		end
	elseif sDefenderNodeType == 'ct' then
		if rRoll.sType == 'attack' then
			nDefense = DB.getValue(nodeDefender, 'ac_final', 10);
			nFlatFootedMod = nDefense - DB.getValue(nodeDefender, 'ac_flatfooted', 10);
			nTouchMod = nDefense - DB.getValue(nodeDefender, 'ac_touch', 10);
		else
			nDefense = DB.getValue(nodeDefender, 'cmd', 10);
			nFlatFootedMod = DB.getValue(nodeDefender, 'ac_final', 10) - DB.getValue(nodeDefender, 'ac_flatfooted', 10);
		end
	elseif sDefenderNodeType == 'npc' then
		if rRoll.sType == 'attack' then
			local sAC = DB.getValue(nodeDefender, 'ac', '');
			nDefense = tonumber(string.match(sAC, '^%s*(%d+)')) or 10;

			local sFlatFootedAC = string.match(sAC, 'flat-footed (%d+)');
			if sFlatFootedAC then
				nFlatFootedMod = nDefense - tonumber(sFlatFootedAC);
			else
				nFlatFootedMod = ActorManager35E.getAbilityBonus(rDefender, sDefenseStat);
			end

			local sTouchAC = string.match(sAC, 'touch (%d+)');
			if sTouchAC then nTouchMod = nDefense - tonumber(sTouchAC); end
		else
			local sBABGrp = DB.getValue(nodeDefender, 'babgrp', '');
			local sMatch = string.match(sBABGrp, 'CMD ([+-]?[0-9]+)');
			if sMatch then
				nDefense = tonumber(sMatch) or 10;
			else
				nDefense = 10;
			end

			local sAC = DB.getValue(nodeDefender, 'ac', '');
			local nAC = tonumber(string.match(sAC, '^%s*(%d+)')) or 10;

			local sFlatFootedAC = string.match(sAC, 'flat-footed (%d+)');
			if sFlatFootedAC then
				nFlatFootedMod = nAC - tonumber(sFlatFootedAC);
			else
				nFlatFootedMod = ActorManager35E.getAbilityBonus(rDefender, sDefenseStat);
			end
		end
	end

	nDefenseStatMod = ActorManager35E.getAbilityBonus(rDefender, sDefenseStat) + ActorManager35E.getAbilityBonus(rDefender, sDefenseStat2);

	-- MAKE SURE FLAT-FOOTED AND TOUCH ADJUSTMENTS ARE POSITIVE
	if nTouchMod < 0 then nTouchMod = 0; end
	if nFlatFootedMod < 0 then nFlatFootedMod = 0; end

	-- APPLY FLAT-FOOTED AND TOUCH ADJUSTMENTS
	if bTouch then nDefense = nDefense - nTouchMod; end
	if bFlatFooted then nDefense = nDefense - nFlatFootedMod; end

	-- EFFECT MODIFIERS
	local nDefenseEffectMod = 0;
	local nMissChance = 0;
	if ActorManager.hasCT(rDefender) then
		-- SETUP
		local bCombatAdvantage = false;
		local bZeroAbility = false;
		local nBonusAC = 0;
		local nBonusStat = 0;
		local nBonusSituational = 0;

		local bPFMode = DataCommon.isPFRPG();

		-- BUILD ATTACK FILTER
		local aAttackFilter = {};
		if sAttackType == 'M' then
			table.insert(aAttackFilter, 'melee');
		elseif sAttackType == 'R' then
			table.insert(aAttackFilter, 'ranged');
		end
		if bOpportunity then table.insert(aAttackFilter, 'opportunity'); end

		-- CHECK IF COMBAT ADVANTAGE ALREADY SET BY ATTACKER EFFECT
		if sAttack:match('%[CA%]') then bCombatAdvantage = true; end

		-- GET DEFENDER SITUATIONAL MODIFIERS - GENERAL
		if EffectManager35E.hasEffect(rAttacker, 'CA', rDefender, true) then bCombatAdvantage = true; end
		if EffectManager35E.hasEffect(rAttacker, 'Invisible', rDefender, true) then
			nBonusSituational = nBonusSituational - 2;
			bCombatAdvantage = true;
		end
		if EffectManager35E.hasEffect(rDefender, 'GRANTCA', rAttacker) then bCombatAdvantage = true; end
		if EffectManager35E.hasEffect(rDefender, 'Blinded') then
			nBonusSituational = nBonusSituational - 2;
			bCombatAdvantage = true;
		end
		if EffectManager35E.hasEffect(rDefender, 'Cowering') or EffectManager35E.hasEffect(rDefender, 'Rebuked') then
			nBonusSituational = nBonusSituational - 2;
			bCombatAdvantage = true;
		end
		if EffectManager35E.hasEffect(rDefender, 'Slowed') then nBonusSituational = nBonusSituational - 1; end
		if EffectManager35E.hasEffect(rDefender, 'Flat-footed') or EffectManager35E.hasEffect(rDefender, 'Flatfooted') or
						EffectManager35E.hasEffect(rDefender, 'Climbing') or EffectManager35E.hasEffect(rDefender, 'Running') then bCombatAdvantage = true; end
		if EffectManager35E.hasEffect(rDefender, 'Pinned') then
			bCombatAdvantage = true;
			if bPFMode then
				nBonusSituational = nBonusSituational - 4;
			else
				if not EffectManager35E.hasEffect(rAttacker, 'Grappled') then nBonusSituational = nBonusSituational - 4; end
			end
		elseif not bPFMode and EffectManager35E.hasEffect(rDefender, 'Grappled') then
			if not EffectManager35E.hasEffect(rAttacker, 'Grappled') then bCombatAdvantage = true; end
		end
		if EffectManager35E.hasEffect(rDefender, 'Helpless') or EffectManager35E.hasEffect(rDefender, 'Paralyzed') or
						EffectManager35E.hasEffect(rDefender, 'Petrified') or EffectManager35E.hasEffect(rDefender, 'Unconscious') then
			if sAttackType == 'M' then nBonusSituational = nBonusSituational - 4; end
			bZeroAbility = true;
		end
		if EffectManager35E.hasEffect(rDefender, 'Kneeling') or EffectManager35E.hasEffect(rDefender, 'Sitting') then
			if sAttackType == 'M' then
				nBonusSituational = nBonusSituational - 2;
			elseif sAttackType == 'R' then
				nBonusSituational = nBonusSituational + 2;
			end
		elseif EffectManager35E.hasEffect(rDefender, 'Prone') then
			if sAttackType == 'M' then
				nBonusSituational = nBonusSituational - 4;
			elseif sAttackType == 'R' then
				nBonusSituational = nBonusSituational + 4;
			end
		end
		if EffectManager35E.hasEffect(rDefender, 'Squeezing') then nBonusSituational = nBonusSituational - 4; end
		if EffectManager35E.hasEffect(rDefender, 'Stunned') then
			nBonusSituational = nBonusSituational - 2;
			if rRoll.sType == 'grapple' then nBonusSituational = nBonusSituational - 4; end
			bCombatAdvantage = true;
		end
		if EffectManager35E.hasEffect(rDefender, 'Invisible', rAttacker) then bTotalConceal = true; end

		-- DETERMINE EXISTING AC MODIFIER TYPES
		local aExistingBonusByType = ActorManager35E.getArmorComps(rDefender);

		-- GET DEFENDER ALL DEFENSE MODIFIERS
		local aIgnoreEffects = {};
		if bTouch then
			table.insert(aIgnoreEffects, 'armor');
			table.insert(aIgnoreEffects, 'shield');
			table.insert(aIgnoreEffects, 'natural');
			table.insert(aIgnoreEffects, 'naturalsize');
			table.insert(aIgnoreEffects, 'armorenhancement');
			table.insert(aIgnoreEffects, 'shieldenhancement');
			table.insert(aIgnoreEffects, 'naturalenhancement');
		end
		if bFlatFooted or bCombatAdvantage then table.insert(aIgnoreEffects, 'dodge'); end
		if rRoll.sType == 'grapple' then table.insert(aIgnoreEffects, 'size'); end
		local aACEffects = EffectManager35E.getEffectsBonusByType(rDefender, { 'AC' }, true, aAttackFilter, rAttacker);
		for k, v in pairs(aACEffects) do
			if not StringManager.contains(aIgnoreEffects, k) then
				local sBonusType = DataCommon.actypes[k];
				if sBonusType then
					-- Dodge bonuses stack (by rules)
					if sBonusType == 'dodge' then
						nBonusAC = nBonusAC + v.mod;
						-- Size bonuses stack (by usage expectation)
					elseif sBonusType == 'size' then
						nBonusAC = nBonusAC + v.mod;
					elseif aExistingBonusByType[sBonusType] then
						if v.mod < 0 then
							nBonusAC = nBonusAC + v.mod;
						elseif v.mod > aExistingBonusByType[sBonusType] then
							nBonusAC = nBonusAC + v.mod - aExistingBonusByType[sBonusType];
						end
					else
						nBonusAC = nBonusAC + v.mod;
					end
				else
					nBonusAC = nBonusAC + v.mod;
				end
			end
		end
		if rRoll.sType == 'grapple' then
			local nPFMod, nPFCount = EffectManager35E.getEffectsBonus(rDefender, { 'CMD' }, true, aAttackFilter, rAttacker);
			if nPFCount > 0 then nBonusAC = nBonusAC + nPFMod; end
		end

		-- GET DEFENDER DEFENSE STAT MODIFIERS
		local nBonusStat = 0;
		local nBonusStat1 = ActorManager35E.getAbilityEffectsBonus(rDefender, sDefenseStat);
		if (sDefenderNodeType == 'pc') and (nBonusStat1 > 0) then
			if DB.getValue(nodeDefender, 'encumbrance.armormaxstatbonusactive', 0) == 1 then
				local nCurrentStatBonus = ActorManager35E.getAbilityBonus(rDefender, sDefenseStat);
				local nMaxStatBonus = math.max(DB.getValue(nodeDefender, 'encumbrance.armormaxstatbonus', 0), 0);
				local nMaxEffectStatModBonus = math.max(nMaxStatBonus - nCurrentStatBonus, 0);
				if nBonusStat1 > nMaxEffectStatModBonus then nBonusStat1 = nMaxEffectStatModBonus; end
			end
		end
		if not bFlatFooted and not bCombatAdvantage and sDefenseStat == 'dexterity' then nFlatFootedMod = nFlatFootedMod + nBonusStat1; end
		nBonusStat = nBonusStat + nBonusStat1;
		local nBonusStat2 = ActorManager35E.getAbilityEffectsBonus(rDefender, sDefenseStat2);
		if not bFlatFooted and not bCombatAdvantage and sDefenseStat2 == 'dexterity' then nFlatFootedMod = nFlatFootedMod + nBonusStat2; end
		nBonusStat = nBonusStat + nBonusStat2;
		local nBonusStat3 = ActorManager35E.getAbilityEffectsBonus(rDefender, sDefenseStat3);
		if not bFlatFooted and not bCombatAdvantage and sDefenseStat3 == 'dexterity' then nFlatFootedMod = nFlatFootedMod + nBonusStat3; end
		nBonusStat = nBonusStat + nBonusStat3;
		if bFlatFooted or bCombatAdvantage then
			-- IF NEGATIVE AND AC STAT BONUSES, THEN ONLY APPLY THE AMOUNT THAT EXCEEDS AC STAT BONUSES
			if nBonusStat < 0 then
				if nDefenseStatMod > 0 then nBonusStat = math.min(nDefenseStatMod + nBonusStat, 0); end

				-- IF POSITIVE AND AC STAT PENALTIES, THEN ONLY APPLY UP TO AC STAT PENALTIES
			else
				if nDefenseStatMod < 0 then
					nBonusStat = math.min(nBonusStat, -nDefenseStatMod);
				else
					nBonusStat = 0;
				end
			end
		end

		-- HANDLE NEGATIVE LEVELS
		if rRoll.sType == 'grapple' then
			local nNegLevelMod, nNegLevelCount = EffectManager35E.getEffectsBonus(rDefender, { 'NLVL' }, true);
			if nNegLevelCount > 0 then nBonusSituational = nBonusSituational - nNegLevelMod; end
		end

		-- HANDLE DEXTERITY MODIFIER REMOVAL
		if bZeroAbility then
			if bFlatFooted then
				nBonusSituational = nBonusSituational - 5;
			else
				nBonusSituational = nBonusSituational - nFlatFootedMod - 5;
			end
		elseif bCombatAdvantage and not bFlatFooted then
			nBonusSituational = nBonusSituational - nFlatFootedMod;
		end

		-- GET DEFENDER SITUATIONAL MODIFIERS - COVER
		if nCover < 8 then
			local aCover = EffectManager35E.getEffectsByType(rDefender, 'SCOVER', aAttackFilter, rAttacker);
			if #aCover > 0 or EffectManager35E.hasEffect(rDefender, 'SCOVER', rAttacker) then
				nBonusSituational = nBonusSituational + 8 - nCover;
			elseif nCover < 4 then
				aCover = EffectManager35E.getEffectsByType(rDefender, 'COVER', aAttackFilter, rAttacker);
				if #aCover > 0 or EffectManager35E.hasEffect(rDefender, 'COVER', rAttacker) then
					nBonusSituational = nBonusSituational + 4 - nCover;
				elseif nCover < 2 then
					aCover = EffectManager35E.getEffectsByType(rDefender, 'PCOVER', aAttackFilter, rAttacker);
					if #aCover > 0 or EffectManager35E.hasEffect(rDefender, 'PCOVER', rAttacker) then
						nBonusSituational = nBonusSituational + 2 - nCover;
					end
				end
			end
		end

		-- GET DEFENDER SITUATIONAL MODIFIERS - CONCEALMENT
		local aConceal = EffectManager35E.getEffectsByType(rDefender, 'TCONC', aAttackFilter, rAttacker);
		if #aConceal > 0 or EffectManager35E.hasEffect(rDefender, 'TCONC', rAttacker) or bTotalConceal or bAttackerBlinded then
			nMissChance = 50;
		else
			aConceal = EffectManager35E.getEffectsByType(rDefender, 'CONC', aAttackFilter, rAttacker);
			if #aConceal > 0 or EffectManager35E.hasEffect(rDefender, 'CONC', rAttacker) or bConceal then nMissChance = 20; end
		end

		-- CHECK INCORPOREALITY
		if not bPFMode then
			local bIncorporealAttack = false;
			if string.match(sAttack, '%[INCORPOREAL%]') then bIncorporealAttack = true; end
			local bIncorporealDefender = EffectManager35E.hasEffect(rDefender, 'Incorporeal', rAttacker);

			if bIncorporealDefender and not bIncorporealAttack then nMissChance = 50; end
		end

		-- ADD IN EFFECT MODIFIERS
		nDefenseEffectMod = nBonusAC + nBonusStat + nBonusSituational;

		-- NO DEFENDER SPECIFIED, SO JUST LOOK AT THE ATTACK ROLL MODIFIERS
	else
		if bTotalConceal or bAttackerBlinded then
			nMissChance = 50;
		elseif bConceal then
			nMissChance = 20;
		end

		if bIncorporealAttack then nMissChance = 50; end
	end

	-- Return the final defense value
	return nDefense, 0, nDefenseEffectMod, nMissChance;
end

-- Function Overrides
function onInit()
	if CombatManagerKel then
		ActorManager35E.getDefenseValue = getDefenseValue_kel;
	else
		ActorManager35E.getDefenseValue = getDefenseValue_new;
	end

	-- DataCommon.actypes["armorsize"] = "armorsize"
	DataCommon.actypes['naturalsize'] = 'naturalsize'
	DataCommon.actypes['armorenhancement'] = 'armorenhancement'
	DataCommon.actypes['shieldenhancement'] = 'shieldenhancement'
	DataCommon.actypes['naturalenhancement'] = 'naturalenhancement'

	-- table.insert(DataCommon.bonustypes, "armorsize")
	table.insert(DataCommon.bonustypes, 'naturalsize')
	table.insert(DataCommon.bonustypes, 'armorenhancement')
	table.insert(DataCommon.bonustypes, 'shieldenhancement')
	table.insert(DataCommon.bonustypes, 'naturalenhancement')
end
