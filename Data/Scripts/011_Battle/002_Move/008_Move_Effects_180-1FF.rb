#===============================================================================
# User is protected against damaging moves this round. Decreases the Defense of
# the user of a stopped contact move by 2 stages. (Obstruct)
#===============================================================================
class PokeBattle_Move_184 < PokeBattle_ProtectMove
  def initialize(battle,move)
    super
    @effect = PBEffects::Obstruct
  end
end



#===============================================================================
# Lowers target's Defense and Special Defense by 1 stage at the end of each
# turn. Prevents target from retreating. (Octolock)
#===============================================================================
class PokeBattle_Move_185 < PokeBattle_Move
  def pbFailsAgainstTarget?(user, target)
    return false if damagingMove?
    if target.effects[PBEffects::Octolock] >= 0
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    if Settings::MORE_TYPE_EFFECTS && target.pbHasType?(:GHOST)
      @battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true)))
      return true
    end
    return false
  end

  def pbEffectAgainstTarget(user, target)
    target.effects[PBEffects::Octolock] = user.index
    @battle.pbDisplay(_INTL("{1} can no longer escape because of {2}!", target.pbThis, @name))
  end
end



#===============================================================================
# Ignores move redirection from abilities and moves. (Snipe Shot)
#===============================================================================
class PokeBattle_Move_186 < PokeBattle_Move
  def cannotRedirect?; return true; end
end



#===============================================================================
# Consumes berry and raises the user's Defense by 2 stages. (Stuff Cheeks)
#===============================================================================
class PokeBattle_Move_188 < PokeBattle_StatUpMove
  def initialize(battle, move)
    super
    @statUp = [:DEFENSE, 2]
  end

  def pbCanChooseMove?(user,commandPhase,showMessages)
    item = user.item
    if !item || !item.is_berry? || !user.itemActive?
      if showMessages
        msg = _INTL("{1} can't use that move because it doesn't have a Berry!", user.pbThis)
        (commandPhase) ? @battle.pbDisplayPaused(msg) : @battle.pbDisplay(msg)
      end
      return false
    end
    return true
  end

  def pbMoveFailed?(user,targets)
    # NOTE: Unnerve does not stop a Pokémon using this move.
    item = user.item
    if !item || !item.is_berry? || !user.itemActive?
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return super
  end

  def pbEffectGeneral(user)
    super
    @battle.pbDisplay(_INTL("{1} ate its {2}!", user.pbThis, user.itemName))
    item = user.item
    user.pbConsumeItem(true, false)   # Don't trigger Symbiosis yet
    user.pbHeldItemTriggerCheck(item, false)
  end
end



#===============================================================================
# Forces all active Pokémon to consume their held berries. This move bypasses
# Substitutes. (Teatime)
#===============================================================================
class PokeBattle_Move_187 < PokeBattle_Move
  def ignoresSubstitute?(user); return true; end

  def pbMoveFailed?(user, targets)
    failed = true
    targets.each do |b|
      next if !b.item || !b.item.is_berry?
      next if b.semiInvulnerable?
      failed = false
      break
    end
    if failed
      @battle.pbDisplay(_INTL("But nothing happened!"))
      return true
    end
    return false
  end

  def pbOnStartUse(user,targets)
    @battle.pbDisplay(_INTL("It's teatime! Everyone dug in to their Berries!"))
  end

  def pbFailsAgainstTarget?(user, target)
    return true if !target.item || !target.item.is_berry? || target.semiInvulnerable?
    return false
  end

  def pbEffectAgainstTarget(user, target)
    @battle.pbCommonAnimation("EatBerry", target)
    item = target.item
    target.pbConsumeItem(true, false)   # Don't trigger Symbiosis yet
    target.pbHeldItemTriggerCheck(item, false)
  end
end



#===============================================================================
# Decreases Opponent's Defense by 1 stage. Does Double Damage under gravity
# (Grav Apple)
#===============================================================================
class PokeBattle_Move_213 < PokeBattle_TargetStatDownMove
  def initialize(battle,move)
    super
    @statDown = [:DEFENSE,1]
  end

  def pbBaseDamage(baseDmg,user,target)
    baseDmg = baseDmg * 3 / 2 if @battle.field.effects[PBEffects::Gravity] > 0
    return baseDmg
  end
end



#===============================================================================
# Decrease 1 stage of speed and weakens target to fire moves. (Tar Shot)
#===============================================================================
class PokeBattle_Move_193 < PokeBattle_Move
  def pbFailsAgainstTarget?(user,target)
    if !target.pbCanLowerStatStage?(:SPEED,target,self) && !target.effects[PBEffects::TarShot]
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectAgainstTarget(user,target)
    target.pbLowerStatStage(:SPEED,1,target)
    target.effects[PBEffects::TarShot] = true
    @battle.pbDisplay(_INTL("{1} became weaker to fire!",target.pbThis))
  end
end



#===============================================================================
# Changes Category based on Opponent's Def and SpDef. Has 20% Chance to Poison
# (Shell Side Arm)
#===============================================================================
class PokeBattle_Move_206 < PokeBattle_Move_005
  def initialize(battle, move)
    super
    @calcCategory = 1
  end

  def physicalMove?(thisType = nil); return (@calcCategory == 0); end
  def specialMove?(thisType = nil);  return (@calcCategory == 1); end
  def contactMove?;                  return physicalMove?;        end

  def pbOnStartUse(user, targets)
    target = targets[0]
    stageMul = [2,2,2,2,2,2, 2, 3,4,5,6,7,8]
    stageDiv = [8,7,6,5,4,3, 2, 2,2,2,2,2,2]
    # Calculate user's effective attacking values
    attack_stage         = user.stages[:ATTACK] + 6
    real_attack          = (user.attack.to_f * stageMul[attack_stage] / stageDiv[attack_stage]).floor
    special_attack_stage = user.stages[:SPECIAL_ATTACK] + 6
    real_special_attack  = (user.spatk.to_f * stageMul[special_attack_stage] / stageDiv[special_attack_stage]).floor
    # Calculate target's effective defending values
    defense_stage         = target.stages[:DEFENSE] + 6
    real_defense          = (target.defense.to_f * stageMul[defense_stage] / stageDiv[defense_stage]).floor
    special_defense_stage = target.stages[:SPECIAL_DEFENSE] + 6
    real_special_defense  = (target.spdef.to_f * stageMul[special_defense_stage] / stageDiv[special_defense_stage]).floor
    # Perform simple damage calculation
    physical_damage = real_attack.to_f / real_defense
    special_damage = real_special_attack.to_f / real_special_defense
    # Determine move's category
    if physical_damage == special_damage
      @calcCategry = @battle.pbRandom(2)
    else
      @calcCategory = (physical_damage > special_damage) ? 0 : 1
    end
  end

  def pbShowAnimation(id, user, targets, hitNum = 0, showAnimation = true)
    hitNum = 1 if physicalMove?
    super
  end
end



#===============================================================================
# Hits 3 times and always critical. (Surging Strikes)
#===============================================================================
class PokeBattle_Move_189 < PokeBattle_Move
  def multiHitMove?;                   return true; end
  def pbNumHits(user, targets);        return 3;    end
  def pbCritialOverride(user, target); return 1;    end
end

#===============================================================================
# Restore HP and heals any status conditions of itself and its allies
# (Jungle Healing)
#===============================================================================
class PokeBattle_Move_210 < PokeBattle_Move
  def healingMove?; return true; end

  def pbMoveFailed?(user,targets)
    failed = true
    @battle.eachSameSideBattler(user) do |b|
      next if b.status == :NONE && !b.canHeal?
      failed = false
      break
    end
    if failed
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbFailsAgainstTarget?(user,target)
    return target.status == :NONE && !target.canHeal?
  end

  def pbEffectAgainstTarget(user,target)
    if target.canHeal?
      target.pbRecoverHP(target.totalhp / 4)
      @battle.pbDisplay(_INTL("{1}'s HP was restored.", target.pbThis))
    end
    if target.status != :NONE
      old_status = target.status
      target.pbCureStatus(false)
      case old_status
      when :SLEEP
        @battle.pbDisplay(_INTL("{1} was woken from sleep.", target.pbThis))
      when :POISON
        @battle.pbDisplay(_INTL("{1} was cured of its poisoning.", target.pbThis))
      when :BURN
        @battle.pbDisplay(_INTL("{1}'s burn was healed.", target.pbThis))
      when :PARALYSIS
        @battle.pbDisplay(_INTL("{1} was cured of paralysis.", target.pbThis))
      when :FROZEN
        @battle.pbDisplay(_INTL("{1} was thawed out.", target.pbThis))
      end
    end
  end
end



#===============================================================================
# Changes type and base power based on Battle Terrain (Terrain Pulse)
#===============================================================================
class PokeBattle_Move_203 < PokeBattle_Move
  def pbBaseDamage(baseDmg,user,target)
    baseDmg *= 2 if @battle.field.terrain != :None && user.affectedByTerrain?
    return baseDmg
  end

  def pbBaseType(user)
    ret = :NORMAL
    return ret if !user.affectedByTerrain?
    case @battle.field.terrain
    when :Electric
      ret = :ELECTRIC if GameData::Type.exists?(:ELECTRIC)
    when :Grassy
      ret = :GRASS if GameData::Type.exists?(:GRASS)
    when :Misty
      ret = :FAIRY if GameData::Type.exists?(:FAIRY)
    when :Psychic
      ret = :PSYCHIC if GameData::Type.exists?(:PSYCHIC)
    end
    return ret
  end

  def pbShowAnimation(id,user,targets,hitNum=0,showAnimation=true)
    t = pbBaseType(user)
    hitNum = 1 if t == :ELECTRIC
    hitNum = 2 if t == :GRASS
    hitNum = 3 if t == :FAIRY
    hitNum = 4 if t == :PSYCHIC
    super
  end
end



#===============================================================================
# Burns opposing Pokemon that have increased their stats in that turn before the
# execution of this move (Burning Jealousy)
#===============================================================================
class PokeBattle_Move_209 < PokeBattle_BurnMove
  def pbAdditionalEffect(user, target)
    super if target.statsRaised
  end
end



#===============================================================================
# Move has increased Priority in Grassy Terrain (Grassy Glide)
#===============================================================================
class PokeBattle_Move_211 < PokeBattle_Move
  def pbPriority(user)
    ret = super
    ret += 1 if @battle.field.terrain == :Grassy && user.affectedByTerrain?
    return ret
  end
end


#===============================================================================
# Power Doubles on Electric Terrain (Rising Voltage)
#===============================================================================
class PokeBattle_Move_201 < PokeBattle_Move
  def pbBaseDamage(baseDmg,user,target)
    baseDmg *= 2 if @battle.field.terrain == :Electric && target.affectedByTerrain?
    return baseDmg
  end
end



#===============================================================================
# Boosts Targets' Attack and Defense (Coaching)
#===============================================================================
class PokeBattle_Move_200 < PokeBattle_TargetMultiStatUpMove
  def initialize(battle,move)
    super
    @statUp = [:ATTACK,1,:DEFENSE,1]
  end

  def pbMoveFailed?(user,targets)
    @validTargets = []
    @battle.eachSameSideBattler(user) do |b|
      next if !b.pbCanRaiseStatStage?(:ATTACK,user,self) &&
              !b.pbCanRaiseStatStage?(:DEFENSE,user,self)
      next if b.index == user.index
      @validTargets.push(b)
    end
    if @validTargets.length==0
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbFailsAgainstTarget?(user,target)
    ret = super
    return true if !@validTargets.any? { |b| b.index == target.index }
    return ret
  end
end



#===============================================================================
# Renders item unusable (Corrosive Gas)
#===============================================================================
class PokeBattle_Move_1A1 < PokeBattle_Move
  def pbFailsAgainstTarget?(user, target)
    # unlosableItem already checks for whether the item is corroded
    if !target.item || target.unlosableItem?(target.item) ||
       target.effects[PBEffects::Substitute] > 0
      @battle.pbDisplay(_INTL("{1} is unaffected!", target.pbThis))
      return true
    end
    if target.hasActiveAbility?(:STICKYHOLD) && !@battle.moldBreaker
      @battle.pbShowAbilitySplash(target)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        @battle.pbDisplay(_INTL("{1} is unaffected!", target.pbThis))
      else
        @battle.pbDisplay(_INTL("{1} is unaffected because of its {2}!",
           target.pbThis(true), target.abilityName))
      end
      @battle.pbHideAbilitySplash(target)
      return true
    end
    return false
  end

  def pbEffectAgainstTarget(user, target)
    target.setCorrodedItem
    target.setRecycleItem(nil)
    target.effects[PBEffects::PickupItem] = nil
    target.effects[PBEffects::PickupUse]  = 0
    @battle.pbDisplay(_INTL("{1} corroded {2}'s {3}!",
       user.pbThis, target.pbThis(true), target.itemName))
  end
end



#===============================================================================
# Power is boosted on Psychic Terrain (Expanding Force)
#===============================================================================
class PokeBattle_Move_207 < PokeBattle_Move
  def pbTarget(user)
    if @battle.field.terrain == :Psychic && user.affectedByTerrain?
      return GameData::Target.get(:AllNearFoes)
    end
    return super
  end

  def pbBaseDamage(baseDmg,user,target)
    if @battle.field.terrain == :Psychic && user.affectedByTerrain?
      baseDmg = baseDmg * 3 / 2
    end
    return baseDmg
  end
end



#===============================================================================
# Boosts Sp Atk on 1st Turn and Attacks on 2nd (Meteor Beam)
#===============================================================================
class PokeBattle_Move_190 < PokeBattle_TwoTurnMove
  def pbChargingTurnMessage(user,targets)
    @battle.pbDisplay(_INTL("{1} is overflowing with space power!",user.pbThis))
  end

  def pbChargingTurnEffect(user,target)
    if user.pbCanRaiseStatStage?(:SPECIAL_ATTACK,user,self)
      user.pbRaiseStatStage(:SPECIAL_ATTACK,1,user)
    end
  end
end



#===============================================================================
# Fails if the Target has no Item (Poltergeist)
#===============================================================================
class PokeBattle_Move_204 < PokeBattle_Move
  def pbFailsAgainstTarget?(user,target)
    if !target.item || !target.itemActive?
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    @battle.pbDisplay(_INTL("{1} is about to be attacked by its {2}!", target.pbThis, target.itemName))
    return false
  end
end



#===============================================================================
# Reduces Defense and Raises Speed after all hits (Scale Shot)
#===============================================================================
class PokeBattle_Move_0C0 < PokeBattle_Move_0C0
  def pbEffectAfterAllHits(user,target)
    if user.pbCanRaiseStatStage?(:SPEED,user,self)
      user.pbRaiseStatStage(:SPEED,1,user)
    end
    if user.pbCanLowerStatStage?(:DEFENSE,target)
      user.pbLowerStatStage(:DEFENSE,1,user)
    end
  end
end



#===============================================================================
# Double damage if stats were lowered that turn. (Lash Out)
#===============================================================================
class PokeBattle_Move_208 < PokeBattle_Move
  def pbBaseDamage(baseDmg,user,target)
    baseDmg *= 2 if user.statsLowered
    return baseDmg
  end
end



#===============================================================================
# Removes all Terrain. Fails if there is no Terrain (Steel Roller)
#===============================================================================
class PokeBattle_Move_205 < PokeBattle_Move
  def pbMoveFailed?(user,targets)
    if @battle.field.terrain == :None
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectGeneral(user)
    case @battle.field.terrain
    when :Electric
      @battle.pbDisplay(_INTL("The electricity disappeared from the battlefield."))
    when :Grassy
      @battle.pbDisplay(_INTL("The grass disappeared from the battlefield."))
    when :Misty
      @battle.pbDisplay(_INTL("The mist disappeared from the battlefield."))
    when :Psychic
      @battle.pbDisplay(_INTL("The weirdness disappeared from the battlefield."))
    end
    @battle.field.terrain = :None
  end
end



#===============================================================================
# Self KO. Boosted Damage when on Misty Terrain (Misty Explosion)
#===============================================================================
class PokeBattle_Move_202 < PokeBattle_Move_0E0
  def pbBaseDamage(baseDmg,user,target)
    baseDmg = baseDmg * 3 / 2 if @battle.field.terrain == :Misty && user.affectedByTerrain?
    return baseDmg
  end
end



#===============================================================================
# Target becomes Psychic type. (Magic Powder)
#===============================================================================
class PokeBattle_Move_194 < PokeBattle_Move
  def pbFailsAgainstTarget?(user,target)
    if !target.canChangeType? || !GameData::Type.exists?(:PSYCHIC) ||
       !target.pbHasOtherType?(:PSYCHIC) || !target.affectedByPowder?
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectAgainstTarget(user,target)
    target.pbChangeTypes(:PSYCHIC)
    typeName = GameData::Type.get(:PSYCHIC).name
    @battle.pbDisplay(_INTL("{1}'s type changed to {2}!", target.pbThis, typeName))
  end
end

#===============================================================================
# Target's last move used loses 3 PP. (Eerie Spell)
#===============================================================================
class PokeBattle_Move_215 < PokeBattle_Move
  def pbFailsAgainstTarget?(user,target)
    failed = true
    target.eachMove do |m|
      next if m.id != target.lastRegularMoveUsed || m.pp==0 || m.total_pp<=0
      failed = false; break
    end
    if failed
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectAgainstTarget(user,target)
    target.eachMove do |m|
      next if m.id != target.lastRegularMoveUsed
      reduction = [3,m.pp].min
      target.pbSetPP(m,m.pp-reduction)
      @battle.pbDisplay(_INTL("It reduced the PP of {1}'s {2} by {3}!",
         target.pbThis(true),m.name,reduction))
      break
    end
  end
end

#===============================================================================
# The user takes recoil damage equal to 1/2 of its total HP (rounded up, min. 1
# damage). (Steel Beam)
#===============================================================================
class PokeBattle_Move_214 < PokeBattle_RecoilMove
  def pbEffectAfterAllHits(user, target)
    return if !user.takesIndirectDamage?
    amt = (user.totalhp / 2.0).ceil
    amt = 1 if amt < 1
    user.pbReduceHP(amt, false)
    @battle.pbDisplay(_INTL("{1} is damaged by recoil!", user.pbThis))
    user.pbItemHPHealCheck
  end
end

#===============================================================================
# Deals double damage to Dynamax Pokémon. Dynamax is not implemented though.
# (Behemoth Blade, Behemoth Bash, Dynamax Cannon)
#===============================================================================
class PokeBattle_Move_19A < PokeBattle_Move
end


#===============================================================================
# May leave the target poisoned, paralyzed or asleep.
# (Dire Claw)
#===============================================================================
class PokeBattle_Move_19B < PokeBattle_Move
  def pbAdditionalEffect(user,target)
    return if target.damageState.substitute
    case @battle.pbRandom(3)
    when 0 then target.pbPoison(user) if target.pbCanPoison?(user, false, self)
    when 1 then target.pbSleep if target.pbCanSleep?(user, false, self)
    when 2 then target.pbParalyze(user) if target.pbCanParalyze?(user, false, self)
    end
  end
end

#===============================================================================
# May poison the target. Causes double the damage if target is poisoned.
# (Barb Barrage)
#===============================================================================
class PokeBattle_Move_19C < PokeBattle_Move_07B
  def pbAdditionalEffect(user,target)
    return if target.damageState.substitute

    if @battle.pbRandom(100) < 50
      target.pbPoison(user) if target.pbCanPoison?(user, false, self)
    end
  end
end

#===============================================================================
# 50% chance of lowering enemy's defense. 30% chance of flinching enemy.
# (Triple Arrows)
#===============================================================================
class PokeBattle_Move_19D < PokeBattle_Move
  def flinchingMove?; return true; end

  def pbAdditionalEffect(user, target)
    return if target.damageState.substitute

    if @battle.pbRandom(100) < 50
      if target.pbCanLowerStatStage?(:DEFENSE, user, self)
        target.pbLowerStatStage(:DEFENSE, 1, user)
      end
    end

    if @battle.pbRandom(100) < 30
      target.pbFlinch(user)
    end
  end
end

#===============================================================================
# Raises the user's Attack, Defense and Speed by one stage each.
# (Victory Dance)
#===============================================================================
class PokeBattle_Move_19F < PokeBattle_MultiStatUpMove
  def initialize(battle,move)
    super
    @statUp = [:ATTACK,1,:DEFENSE,1,:SPEED,1]
  end
end

#===============================================================================
# Deals damage and has a 30% chance of burning the target. 
# If the target already has a status condition, its power is doubled.
# (Infernal Parade)
#===============================================================================
class PokeBattle_Move_20A < PokeBattle_Move
  def pbBaseDamage(baseDmg,user,target)
    if target.burned? &&
       (target.effects[PBEffects::Substitute]==0 || ignoresSubstitute?(user))
      baseDmg *= 2
    end
    return baseDmg
  end
  def pbAdditionalEffect(user,target)
    return if target.damageState.substitute

    if @battle.pbRandom(100) < 30
      target.pbBurn(user) if target.pbCanBurn?(user, false, self)
    end
  end
end

#===============================================================================
# Heals user's status conditions.
# Raises the user's Special Attack and Special Defense.
# (Take Heart)
#===============================================================================
class PokeBattle_Move_20B < PokeBattle_Move_02C
  def pbEffectGeneral(user)
    super

    old_status = user.status
    user.pbCureStatus(false)
    case old_status
    when :BURN
      @battle.pbDisplay(_INTL("{1} healed its burn!",user.pbThis))
    when :POISON
      @battle.pbDisplay(_INTL("{1} cured its poisoning!",user.pbThis))
    when :PARALYSIS
      @battle.pbDisplay(_INTL("{1} cured its paralysis!",user.pbThis))
    when :FROZEN
        @battle.pbDisplay(_INTL("{1} was thawed out.", user.pbThis))
    when :SLEEP
        @battle.pbDisplay(_INTL("{1} was woken from sleep.", user.pbThis))
    end
  end
end

#===============================================================================
# 30% Chance of confusing the target.
# If it misses, the user takes crash damage equal to half of its maximum HP.
# (Axe Kick)
#===============================================================================
class PokeBattle_Move_20C < PokeBattle_Move_10B
  def pbAdditionalEffect(user, target)
    return if target.damageState.substitute
    if @battle.pbRandom(100) < 30
      target.pbConfuse(user) if target.pbCanConfuse?(user, false, self)
    end
  end
end

#===============================================================================
# Switches out and summons a snowstorm. (Chilly Reception)
#===============================================================================
class PokeBattle_Move_20D < PokeBattle_Move_102
  def pbEndOfMoveUsageEffect(user,targets,numHits,switchedBattlers) 
    super  
    @battle.pbDisplay(_INTL("{1} went back to {2}!",user.pbThis,
      @battle.pbGetOwnerName(user.index)))
    @battle.pbPursuit(user.index)
    return if user.fainted?
    newPkmn = @battle.pbGetReplacementPokemonIndex(user.index)   
    return if newPkmn<0
    @battle.pbRecallAndReplace(user.index,newPkmn)
    @battle.pbClearChoice(user.index)   
    @battle.moldBreaker = false
    switchedBattlers.push(user.index)
    user.pbEffectsOnSwitchIn(true)
  end
end

#===============================================================================
# Deals 33% more damage against super-effective enemies (Collision Course, Electro Drift)
#===============================================================================
class PokeBattle_Move_20E < PokeBattle_Move
  def pbBaseDamage(base_dmg, user, target)
    eff = Effectiveness.calculate(self.type, target.type1, target.type2)
    if Effectiveness.super_effective?(eff)
      base_dmg = (base_dmg * 1.33).round
    end
    return base_dmg
  end
end

#===============================================================================
# Swap user and allies ability to target's ability. (Doodle)
#===============================================================================
class PokeBattle_Move_20F < PokeBattle_Move
  def ignoresSubstitute?(user); return true; end

  def pbFailsAgainstTarget?(user, target)
    if !target.ability || target.unstoppableAbility? ||
       target.ungainableAbility? || target.ability == :WONDERGUARD
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectAgainstTarget(user, target)
    new_ability = target.ability
    @battle.eachSameSideBattler(user) do |battler|
      next if battler.ability == new_ability
      old_ability = battler.ability
      @battle.pbShowAbilitySplash(battler, true, false)
      battler.ability = new_ability
      @battle.pbReplaceAbilitySplash(battler)
      @battle.pbDisplay(_INTL("{1} copied {2}'s Ability!", battler.pbThis, target.pbThis(true)))
      @battle.pbHideAbilitySplash(battler)
      battler.pbOnAbilityChanged(old_ability)
      battler.pbEffectsOnSwitchIn
    end
  end
end

#===============================================================================
# # User loses their Electric type. Fails if user is not Electric-type. (Double Shock)
#===============================================================================
class PokeBattle_Move_216 < PokeBattle_Move
  def pbMoveFailed?(user,targets)
    if !user.pbHasType?(:ELECTRIC)
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectAfterAllHits(user,target)
    if !user.effects[PBEffects::DoubleShock]
      user.effects[PBEffects::DoubleShock] = true
      @battle.pbDisplay(_INTL("{1} used up all of its electricity!",user.pbThis))
    end
  end
end

#===============================================================================
# Lowers HP but sharply boosts Attack, Special Attack, and Speed. (Fillet Away)
#===============================================================================
class PokeBattle_Move_217 < PokeBattle_Move
  def pbMoveFailed?(user, targets)
    hp_loss = [user.totalhp / 2, 1].max
    if user.hp <= hp_loss
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    fail = true
    [:ATTACK, :SPECIAL_ATTACK, :SPEED].each do |stat|
      if user.pbCanRaiseStatStage?(stat, user, self, true)
        fail = false
        break
      end
    end
    if fail
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbEffectGeneral(user)
    hp_loss = [user.totalhp / 2, 1].max
    user.pbReduceHP(hp_loss, false)
    anim_shown = false
    [:ATTACK, :SPECIAL_ATTACK, :SPEED].each do |stat|
      if user.pbCanRaiseStatStage?(stat, user, self)
        user.pbRaiseStatStage(stat, 2, user, anim_shown)
        anim_shown = true
      end
    end
    user.pbItemHPHealCheck
  end
end

#===============================================================================
# Deals damage. Until the end of the user's next turn. Moves targeting the user
# will always hit and deal double damage. (Glaive Rush)
#===============================================================================
class PokeBattle_Move_218 < PokeBattle_Move
  def pbEffectGeneral(user)
    user.effects[PBEffects::GlaiveRush] = 2 
    @battle.pbDisplay(_INTL("{1} is reckless and left itself wide open!", user.pbThis))
  end
end

#===============================================================================
# Deals damage and remove terrains. (Ice Spinner)
#===============================================================================
class PokeBattle_Move_219 < PokeBattle_Move
  def pbEffectGeneral(user)
    case @battle.field.terrain
    when :Electric
      @battle.pbDisplay(_INTL("The electricity disappeared from the battlefield."))
    when :Grassy
      @battle.pbDisplay(_INTL("The grass disappeared from the battlefield."))
    when :Misty
      @battle.pbDisplay(_INTL("The mist disappeared from the battlefield."))
    when :Psychic
      @battle.pbDisplay(_INTL("The weirdness disappeared from the battlefield."))
    end
    @battle.field.terrain = :None
  end
end

#===============================================================================
# The user attacks to avenge its allies. The move’s power increases for each 
# defeated ally. (Last Respects)
#===============================================================================
class PokeBattle_Move_21A < PokeBattle_Move
  def pbBaseDamage(baseDmg, user, target)
    fainted_count = 0

    @battle.eachSameSideBattler(user) do |b|
      next if b.fainted?
      next if b.index == user.index
    end

    party = @battle.pbParty(user.index)
    party.each_with_index do |pkmn, i|
      next if !pkmn || pkmn.hp > 0
      next if i == user.pokemonIndex
      fainted_count += 1
    end

    power = 50 + (50 * fainted_count)
    power = 300 if power > 300
    return power
  end
end  

#===============================================================================
# Removes entry hazards and trap move effects, and poisons opposing Pokémon.
# (Mortal Spin)
#===============================================================================
class PokeBattle_Move_21B < PokeBattle_Move_006
  def pbEffectAfterAllHits(user,target)
    return if user.fainted? || target.damageState.unaffected
    if user.effects[PBEffects::Trapping]>0
      trapMove = GameData::Move.get(user.effects[PBEffects::TrappingMove]).name
      trapUser = @battle.battlers[user.effects[PBEffects::TrappingUser]]
      @battle.pbDisplay(_INTL("{1} got free of {2}'s {3}!",user.pbThis,trapUser.pbThis(true),trapMove))
      user.effects[PBEffects::Trapping]     = 0
      user.effects[PBEffects::TrappingMove] = nil
      user.effects[PBEffects::TrappingUser] = -1
    end
    if user.effects[PBEffects::LeechSeed]>=0
      user.effects[PBEffects::LeechSeed] = -1
      @battle.pbDisplay(_INTL("{1} shed Leech Seed!",user.pbThis))
    end
    if user.pbOwnSide.effects[PBEffects::StealthRock]
      user.pbOwnSide.effects[PBEffects::StealthRock] = false
      @battle.pbDisplay(_INTL("{1} blew away stealth rocks!",user.pbThis))
    end
    if user.pbOwnSide.effects[PBEffects::Spikes]>0
      user.pbOwnSide.effects[PBEffects::Spikes] = 0
      @battle.pbDisplay(_INTL("{1} blew away spikes!",user.pbThis))
    end
    if user.pbOwnSide.effects[PBEffects::ToxicSpikes]>0
      user.pbOwnSide.effects[PBEffects::ToxicSpikes] = 0
      @battle.pbDisplay(_INTL("{1} blew away poison spikes!",user.pbThis))
    end
    if user.pbOwnSide.effects[PBEffects::StickyWeb]
      user.pbOwnSide.effects[PBEffects::StickyWeb] = false
      user.pbOwnSide.effects[PBEffects::StickyWebUser] = -1
      @battle.pbDisplay(_INTL("{1} blew away sticky webs!",user.pbThis))
    end
  end
end

#===============================================================================
# Hits 1-10 times in a row. Each hit has its own accuracy check.
# (Population Bomb)
#===============================================================================
class PokeBattle_Move_21C < PokeBattle_Move
  def pbEffectAgainstTarget(user, target)
    @hitsLanded = 1
    9.times do
      break if target.fainted?

      if @battle.pbRandom(100) >= 90
        @battle.pbDisplay(_INTL("The attack missed!"))
        next
      end
      
      dmg = pbCalcDamage(user, target)
      target.pbReduceHP(dmg, false)
      target.pbItemHPHealCheck
      pbEffectAfterAllHits(user, target)
      @hitsLanded += 1
    end

    if @hitsLanded > 0
      plural = @hitsLanded > 1 ? "times" : "time"
      @battle.pbDisplay(_INTL("{1} hit the target {2} {3}!", user.pbThis, @hitsLanded, plural))
    end
  end
end



#===============================================================================
# The more times the user has been hit by attacks, the greater the move's power.
# (Rage Fist)
#===============================================================================
class PokeBattle_Move_21D < PokeBattle_Move
  def pbBaseDamage(baseDmg, user, target)
    hits_taken = user.effects[PBEffects::RageFist] || 0
    power = 50 + (50 * hits_taken)
    power = 350 if power > 350
    return power
  end
end

#===============================================================================
# Revives one ally.
# (Revival Blessing)
#===============================================================================
class PokeBattle_Move_21E < PokeBattle_Move
  def healingMove?; return true; end

  def pbMoveFailed?(user, targets)
    party = @battle.pbParty(user.index)
    return true if party.none? { |pkmn| pkmn && pkmn.hp == 0 }
    return false
  end

  def pbEffectGeneral(user)
    party = @battle.pbParty(user.index)
    fainted_pokemon = []
    party.each_with_index do |pkmn, i|
      next if !pkmn || pkmn.hp > 0 || i == user.pokemonIndex
      fainted_pokemon << [pkmn, i]
    end
    return if fainted_pokemon.empty?

    choices = fainted_pokemon.map { |pair| pair[0].name }
    choice = @battle.scene.pbShowCommands(_INTL("Choose a Pokémon to revive:"), choices, 1)
    return if choice < 0

    target_pkmn, target_index = fainted_pokemon[choice]

    target_pkmn.hp = (target_pkmn.totalhp / 2).floor
    target_pkmn.hp = 1 if target_pkmn.hp <= 0
    target_pkmn.heal_status
    @battle.scene.pbDisplay(_INTL("{1} revived {2}!", user.pbThis, target_pkmn.name))
  end
end

#===============================================================================
# The user creates a substitute at the cost of 1/2 its max HP, then switches out.
# (Shed Tail)
#===============================================================================
class PokeBattle_Move_21F < PokeBattle_Move
  def pbMoveFailed?(user, targets)
    if user.effects[PBEffects::Substitute] > 0
      @battle.pbDisplay(_INTL("{1} already has a substitute!", user.pbThis))
      return true
    end
    @subLife = user.totalhp / 2
    @subLife = 1 if @subLife < 1
    if user.hp <= @subLife
      @battle.pbDisplay(_INTL("But it does not have enough HP left to make a substitute!"))
      return true
    end
    if !@battle.pbCanChooseNonActive?(user.index)
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbOnStartUse(user, targets)
    user.pbReduceHP(@subLife, false, false)
    user.pbItemHPHealCheck
  end

  def pbEffectGeneral(user)
    user.effects[PBEffects::Trapping]     = 0
    user.effects[PBEffects::TrappingMove] = nil
    user.effects[PBEffects::Substitute]   = @subLife
    @battle.pbDisplay(_INTL("{1} put in a substitute!", user.pbThis))
  end

  def pbEndOfMoveUsageEffect(user, targets, numHits, switchedBattlers)
    return if user.fainted? || numHits == 0
    return if !@battle.pbCanChooseNonActive?(user.index)
    @battle.pbPursuit(user.index)
    return if user.fainted?
    newPkmn = @battle.pbGetReplacementPokemonIndex(user.index)  
    return if newPkmn < 0
    @battle.pbRecallAndReplace(user.index, newPkmn, false, true)
    @battle.pbClearChoice(user.index)   
    @battle.moldBreaker = false
    switchedBattlers.push(user.index)
    user.pbEffectsOnSwitchIn(true)
  end
end

#===============================================================================
# User spins a silken trap to protect itself. 
# Lowers the Speed of any that make direct contact. (Silk Trap)
#===============================================================================
class PokeBattle_Move_220 < PokeBattle_ProtectMove
  def initialize(battle,move)
    super
    @effect = PBEffects::SilkTrap
  end
end

#===============================================================================
# Sharply lower enemy's defense, but raises its attack.
# (Spicy Extract)
#===============================================================================
class PokeBattle_Move_221 < PokeBattle_Move
  def pbMoveFailed?(user, targets)
    target = targets[0]
    failed = !target.pbCanRaiseStatStage?(:ATTACK, user, self) &&
           !target.pbCanLowerStatStage?(:DEFENSE, user, self)
      if failed
        @battle.pbDisplay(_INTL("But it failed!"))
        return true 
      end
    return false
  end

  def pbEffectAgainstTarget(user, target)
    target.pbRaiseStatStage(:ATTACK, 2, user) if target.pbCanRaiseStatStage?(:ATTACK, user, self)
    target.pbLowerStatStage(:DEFENSE, 2, user) if target.pbCanLowerStatStage?(:DEFENSE, user, self)
  end
end

#===============================================================================
# Harshly lowers user's speed
# (Spin Out)
#===============================================================================
class PokeBattle_Move_222 < PokeBattle_StatDownMove
  def initialize(battle,move)
    super
    @statDown = [:SPEED,2]
  end
end

#===============================================================================
# Raises user's Attack and Speed by 1 stage.
# Removes substitutes from all battlers.
# Clears entry hazards from both sides. (Tidy Up)
#===============================================================================
class PokeBattle_Move_223 < PokeBattle_Move
  def pbEffectGeneral(user)
    user.pbRaiseStatStage(:ATTACK, 1, user) if user.pbCanRaiseStatStage?(:ATTACK, user, self)
    user.pbRaiseStatStage(:SPEED, 1, user) if user.pbCanRaiseStatStage?(:SPEED, user, self)

    @battle.eachBattler do |b|
      if b.effects[PBEffects::Substitute] > 0
        b.effects[PBEffects::Substitute] = 0
        @battle.pbDisplay(_INTL("{1}'s substitute faded!", b.pbThis(true)))
      end
    end

    remove_side_hazards(user.pbOwnSide, user)
    remove_side_hazards(user.pbOpposingSide, user)
  end

  private

  def remove_side_hazards(side, user)
    if side.effects[PBEffects::StealthRock]
      side.effects[PBEffects::StealthRock] = false
      @battle.pbDisplay(_INTL("{1} blew away stealth rocks!", user.pbThis))
    end
    if side.effects[PBEffects::Spikes] > 0
      side.effects[PBEffects::Spikes] = 0
      @battle.pbDisplay(_INTL("{1} blew away spikes!", user.pbThis))
    end
    if side.effects[PBEffects::ToxicSpikes] > 0
      side.effects[PBEffects::ToxicSpikes] = 0
      @battle.pbDisplay(_INTL("{1} blew away poison spikes!", user.pbThis))
    end
    if side.effects[PBEffects::StickyWeb]
      side.effects[PBEffects::StickyWeb] = false
      side.effects[PBEffects::StickyWebUser] = -1
      @battle.pbDisplay(_INTL("{1} blew away sticky webs!", user.pbThis))
    end
  end
end

#===============================================================================
# Hits 3 times. No additional effects.
# (Triple Dive)
#===============================================================================
class PokeBattle_Move_224 < PokeBattle_Move
  def multiHitMove?;                   return true; end
  def pbNumHits(user, targets);        return 3;    end
end

#===============================================================================
# If the current terrain is Electric Terrain, this move's power is multiplied by 1.5.
# (Psyblade)
#===============================================================================
class PokeBattle_Move_225 < PokeBattle_Move
  def pbBaseDamage(baseDmg, user, target)
    if @battle.field.terrain == :Electric
      baseDmg = (baseDmg * 1.5).round
    end
    return baseDmg
  end
end

#===============================================================================
# Cannot be selected the turn after it's used.
# (Blood Moon)
#===============================================================================
class PokeBattle_Move_226 < PokeBattle_Move
  def pbEffectAfterAllHits(user, target)
    user.effects[PBEffects::BloodMoon] = 2
  end
end

#===============================================================================
# Drains 50% of damage dealt. 20% chance to burn the target.
# If the target is frozen, it thaws out.
# (Matcha Gotcha)
#===============================================================================
class PokeBattle_Move_227 < PokeBattle_Move
  def healingMove?; return true; end

  def pbAdditionalEffect(user, target)
    return if target.damageState.substitute
    target.pbCureStatus if target.status == :FROZEN
    if @battle.pbRandom(100) < 20
      target.pbBurn(user) if target.pbCanBurn?(user, false, self)
    end
  end

  def pbEffectAgainstTarget(user, target)
    return if target.damageState.hpLost <= 0
    hpGain = (target.damageState.hpLost / 2.0).round
    if user.hasActiveItem?(:BIGROOT)
      hpGain = (hpGain * 1.3).floor
    end
    user.pbRecoverHPFromDrain(hpGain, target)
  end
end

#===============================================================================
# If the move hits, it causes the target's speed to be lowered by 1 stage
# at the end of each turn for 3 turns.
# (Syrup Bomb)
#===============================================================================
class PokeBattle_Move_228 < PokeBattle_Move
  def pbEffectAgainstTarget(user, target)
    return if target.fainted?
    target.effects[PBEffects::SyrupBomb] = 3
    @battle.pbDisplay(_INTL("{1} got doused in syrup!", target.pbThis))
  end
end

#===============================================================================
# This attack charges on the first turn and executes on the second. 
# Raises the user's Special Attack by 1 stage on the first turn. 
# If the user is holding a Power Herb or the weather is Primordial Sea or Rain Dance, 
# the move completes in one turn.
# (Electro Shot)
#===============================================================================
class PokeBattle_Move_229 < PokeBattle_TwoTurnMove
  def pbIsChargingTurn?(user)
    ret = super
    if !user.effects[PBEffects::TwoTurnAttack]
      if [:Rain, :HeavyRain].include?(user.effectiveWeather)
        @powerHerb = false
        @chargingTurn = true
        @damagingTurn = true
      end
    end
    return ret
  end

  def pbChargingTurnMessage(user,targets)
    @battle.pbDisplay(_INTL("{1} absorbed electricity!",user.pbThis))
    if user.pbCanRaiseStatStage?(:SPECIAL_ATTACK, user, self)
      user.pbRaiseStatStage(:SPECIAL_ATTACK, 1, user)
    end
  end
end

#===============================================================================
# Has a 30% chance this move's power is doubled.
# (Fickle Beam)
#===============================================================================
class PokeBattle_Move_22A < PokeBattle_Move
  def pbBaseDamage(baseDmg, user, target)
    if @battle.pbRandom(100) < 30
      baseDmg *= 2
      @battle.pbDisplay(_INTL("{1}'s power surged unpredictably!", user.pbThis))
    end
    return baseDmg
  end
end

#===============================================================================
# Hits twice and never miss.
# (Tachyon Cutter)
#===============================================================================
class PokeBattle_Move_22B < PokeBattle_Move
  def pbAccuracyCheck(user,target); return true; end
  def multiHitMove?;           return true; end
  def pbNumHits(user,targets); return 2;    end
end

#===============================================================================
# Power is equal to 100 * (target's current HP / target's maximum HP), 
# rounded half down, but not less than 1. (Hard Press)
#===============================================================================
class PokeBattle_Move_22C < PokeBattle_Move
  def pbBaseDamage(baseDmg, user, target)
    ratio = target.hp / target.totalhp
    power = (100 * ratio).floor
    return [power, 1].max
  end
end

#===============================================================================
# The user is protected from most attacks made by other Pokemon during this turn,
# and Pokemon trying to make contact with the user become burned. (Burning Bulwark)
#===============================================================================
class PokeBattle_Move_22D < PokeBattle_ProtectMove
  def initialize(battle,move)
    super
    @effect = PBEffects::BurningBulwark
  end

  def pbProtectMessage(user)
    @battle.pbDisplay(_INTL("{1} braced itself with a burning shield!", user.pbThis))
  end
end

#===============================================================================
# Raises the target's chance for a critical hit by 1 stage, or by 2 stages if the
# target is Dragon type. (Dragon Cheer)
#===============================================================================
class PokeBattle_Move_22E < PokeBattle_Move
  def pbMoveFailed?(user, targets)
    @validTargets = []
    @battle.eachSameSideBattler(user) do |b|
      next if b.index == user.index
      next if b.effects[PBEffects::FocusEnergy] > 0
      @validTargets.push(b)
    end
    if @validTargets.length == 0
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end

  def pbFailsAgainstTarget?(user, target)
    return false if @validTargets.any? { |b| b.index == target.index }
    @battle.pbDisplay(_INTL("{1} is already pumped!", target.pbThis)) 
    return true
  end

  def pbEffectAgainstTarget(user, target)
    amount = target.pbHasType?(:DRAGON) ? 2 : 1
    target.effects[PBEffects::FocusEnergy] = amount
    @battle.pbDisplay(_INTL("{1} is pumped up with Dragon Cheer!", target.pbThis))
  end
end

#===============================================================================
# 100% chance of confusing the target if it has any stat raised. (Alluring Voice)
#===============================================================================
class PokeBattle_Move_22F < PokeBattle_ConfuseMove
  def pbAdditionalEffect(user, target)
    if target.statsRaised
      super
      @battle.pbDisplay(_INTL("{1} became confused by the alluring voice!", target.pbThis))
    end
  end
end

#===============================================================================
# Crash Damage and Minimize ignore. (Supercell Slam)
#===============================================================================
class PokeBattle_Move_230 < PokeBattle_Move
  def recoilMove?; return true; end
  def tramplesMinimize?(param = 1); return true; end

  def pbCrashDamage(user)
    return if !user.takesIndirectDamage?
    @battle.pbDisplay(_INTL("{1} kept going and crashed!",user.pbThis))
    @battle.scene.pbDamageAnimation(user)
    user.pbReduceHP(user.totalhp/2,false)
    user.pbItemHPHealCheck
    user.pbFaint if user.fainted?
  end
end

#===============================================================================
# Flinch the target, but fails if target dont select a priority move. (Upper Hand)
#===============================================================================
class PokeBattle_Move_231 < PokeBattle_FlinchMove
  def pbMoveFailed?(user, targets)
    target = targets[0]
    if @battle.choices[target.index][0] == :UseMove &&
       @battle.choices[user.index][0] == :UseMove
      targetMove = @battle.choices[target.index][2]
      userMove   = @battle.choices[user.index][2]
      if @battle.choices[target.index][1] < @battle.choices[user.index][1]
        @battle.pbDisplay(_INTL("But it failed!"))
        return true
      end
      # Falha se o alvo não usou um movimento com prioridade > 0
      if targetMove.priority <= 0
        @battle.pbDisplay(_INTL("But it failed!"))
        return true
      end
    else
      @battle.pbDisplay(_INTL("But it failed!"))
      return true
    end
    return false
  end
end

#===============================================================================
# Increase the user's stat by 1 stage depending on the commanding Tatsugiri. 
# (Order Up)
#===============================================================================
class PokeBattle_Move_232 < PokeBattle_Move
  def pbEffectGeneral(user)
    return if !user.isCommanderHost?
    commander_data = user.effects[PBEffects::Commander]
    return if !commander_data.is_a?(Array) || commander_data.length < 2

    tatsugiri_index = commander_data[0]
    tatsugiri = @battle.battlers[tatsugiri_index]
    if tatsugiri
      @battle.scene.sprites["pokemon_#{tatsugiri.index}"].visible = false
      @battle.choices[tatsugiri.index][0] = :None
    end

    form = commander_data[1]
    stat = [:ATTACK, :DEFENSE, :SPEED][form]
    if user.pbCanRaiseStatStage?(stat, user, self)
      user.pbRaiseStatStage(stat, 1, user, true)
    end
  end
end

#===============================================================================
# Changes type depending on Tauro's breed. Breaks Reflect and Light Screen
# (Raging Bull)
#===============================================================================
class PokeBattle_Move_233 < PokeBattle_Move
  def pbBaseType(user)
    return :NORMAL if user.species != :TAUROS
    case user.form
    when 1 then return :FIGHTING # Combat Breed
    when 2 then return :FIRE     # Blaze Breed
    when 3 then return :WATER    # Aqua Breed
    else       return :NORMAL  
    end
  end

  def pbEffectAfterAllHits(user, target)
    return if target.damageState.substitute
    if target.pbOwnSide.effects[PBEffects::Reflect] > 0
      target.pbOwnSide.effects[PBEffects::Reflect] = 0
      @battle.pbDisplay(_INTL("{1}'s Reflect wore off!", target.pbTeam(true)))
    end
    if target.pbOwnSide.effects[PBEffects::LightScreen] > 0
      target.pbOwnSide.effects[PBEffects::LightScreen] = 0
      @battle.pbDisplay(_INTL("{1}'s Light Screen wore off!", target.pbTeam(true)))
    end
  end
end

# NOTE: If you're inventing new move effects, use function code 19B and onwards.
#       Actually, you might as well use high numbers like 500+ (up to FFFF),
#       just to make sure later additions to Essentials don't clash with your
#       new effects.
