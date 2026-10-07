#!/usr/bin/env python3
"""Writes res://data/quests/*.tres (QuestDef): the quests and events that turn up on their own, and the links that chain them.

The structure is Zombasite's (docs/zombasite-world-and-npcs.md, section 5: a chance to turn up, chains on start / complete / fail,
rewards that move how townspeople feel); the wording, numbers and cast are Curse's own. Edit the tables and re-run.

kind: kill_group | slay_unique | fetch | matter | world (see game/data/quest_def.gd)."""
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "data" / "quests"


def link(quest, chance):
    return {"quest": quest, "chance": chance}


QUESTS = {
    # --- Posted by the Warden: things to kill on the road -----------------------------------------------------------------------
    "ghoul_cull": dict(
        title="Thin the Ghouls", giver="hale", kind="kill_group", target="ghoul", count=8, days=5, weight=3.0,
        text="The ghouls are working the trees along the road and the carters will not pass. Put eight of them down.",
        thanks="Eight less. The carters will risk it again.", fail_text="The road stayed closed. Folk went hungry for it.",
        reward={"gold": 70, "xp": 60, "happy": {"hale": 4}}, penalty={"happy": {"hale": -4}},
        links={"complete": [link("grey_alpha", 0.3)]}),
    "grey_alpha": dict(
        title="The Grey Alpha", giver="hale", kind="slay_unique", target="ghoul", unique_name="Greywhisker", unique_hp=5.0,
        unique_level=1.5, zone=[50, 140], days=6, weight=0.0,
        text="Whoever was leading them is still out there. The carters call it Greywhisker. Find it before it finds the gate.",
        thanks="Greywhisker's head on a stick. That will keep them quiet.", fail_text="Greywhisker kept hunting. The road is not safe.",
        reward={"gold": 90, "xp": 110, "happy": {"all": 3}}, penalty={"happy": {"all": -3}}),
    "spitter_cull": dict(
        title="Spit and Rot", giver="hale", kind="kill_group", target="spitter", count=6, days=5, weight=2.0, min_jobs=1,
        text="The spitters are fouling the wells along the road. Six of them dead and the water might run clean again.",
        thanks="Cleaner water by the week's end. Take this.", fail_text="The wells turned. We are boiling everything now.",
        reward={"gold": 80, "xp": 70, "potions": 2}, penalty={"food": -2}),
    "bloater_cull": dict(
        title="Bursting at the Seams", giver="hale", kind="kill_group", target="bloater", count=4, days=6, weight=1.5, min_jobs=2,
        text="Four bloaters, they say, wandering where they should not. Kill them far from anything we would like to keep.",
        thanks="Not a window broken. Well done.", fail_text="One got close to the granary before it burst. We lost food.",
        reward={"gold": 90, "xp": 90, "food": 3}, penalty={"food": -3}),
    "brute_bounty": dict(
        title="Bounty on Gorran", giver="hale", kind="slay_unique", target="brute", unique_name="Gorran Hollow-Eye", unique_hp=3.5,
        unique_level=1.6, zone=[100, 220], days=6, weight=1.5, min_jobs=1,
        text="Gorran Hollow-Eye walked off the gallows and has been killing patrols ever since. The town will pay for his head.",
        thanks="Hollow-Eye is finished. The town sleeps better.", fail_text="Gorran took two more patrols before the week was out.",
        reward={"gold": 120, "xp": 150, "happy": {"hale": 6}}, penalty={"happy": {"hale": -6}},
        links={"complete": [link("stolen_ledger", 0.25)]}),
    "stolen_ledger": dict(
        title="The Warden's Ledger", giver="hale", kind="fetch", target="brute", item_name="Hale's ledger", count=12, days=6, weight=0.0,
        text="Gorran had my ledger on him, the one with the grain counts. Whatever kills a brute out there, look through its pockets.",
        thanks="Every column intact. You have no idea what this saves me.", fail_text="Without the ledger I cannot prove what we are owed.",
        reward={"gold": 70, "xp": 80, "happy": {"hale": 8}}, penalty={"happy": {"hale": -8}},
        links={"fail": [link("tainted_grain", 0.4)]}),
    # --- Posted by the healer ---------------------------------------------------------------------------------------------------
    "lost_satchel": dict(
        title="Maren's Satchel", giver="maren", kind="fetch", target="zombie", item_name="herb satchel", count=10, days=6, weight=2.0,
        text="I dropped my satchel of dried herbs on the road, and the dead are wearing it now. I need it back. I can do nothing for the sick without it.",
        thanks="My herbs. Bless you. Here, take what I can spare.", fail_text="Without the herbs I can only sit with the sick.",
        reward={"potions": 3, "xp": 60, "happy": {"maren": 8}}, penalty={"happy": {"maren": -6}},
        links={"fail": [link("fever", 0.5)]}),
    "ashgrave": dict(
        title="Mother Ashgrave", giver="maren", kind="slay_unique", target="priest", unique_name="Mother Ashgrave", unique_hp=3.0,
        unique_level=1.7, zone=[200, 300], days=7, weight=1.2, min_jobs=2,
        text="The shrine priests answer to someone, a woman I knew once. They call her Mother Ashgrave now. End it, for her sake and ours.",
        thanks="She was not herself for a long time. Thank you.", fail_text="The shrine is louder than ever.",
        reward={"gold": 60, "xp": 130, "potions": 3, "happy": {"maren": 10}}, penalty={"happy": {"maren": -8}}),
    # --- Matters of the town: they turn up on their own and want a decision ------------------------------------------------------
    "fever": dict(
        title="Fever in the Hearth", giver="maren", kind="matter", days=2, weight=2.0,
        text="{victim} is burning up. The healer says a poultice would break it, or two potions, or we can wait and hope.",
        thanks="The fever broke by morning.", fail_text="{victim} is worse, and the fever has started to move.",
        reward={"happy": {"all": 2, "maren": 4}}, penalty={"happy": {"{victim}": -15, "all": -3}},
        choices=[
            {"label": "Pay Maren for a poultice (25 gold)", "cost": {"gold": 25}, "outcome": "solve", "result": "Maren sets to work."},
            {"label": "Spend two potions", "cost": {"potions": 2}, "outcome": "solve", "result": "The potions do what the poultice would have."},
            {"label": "Wait it out", "cost": {}, "outcome": "fail", "result": "You leave it to chance."}],
        links={"fail": [link("spreading_fever", 0.6)]}),
    "spreading_fever": dict(
        title="The Fever Spreads", giver="maren", kind="matter", days=2, weight=0.0,
        text="Now two more are down. Maren wants to burn the bedding and brew in bulk. It will not be cheap.",
        thanks="Caught in time. Nobody else took it.", fail_text="The fever ran through the hearth. It will be a hard week.",
        reward={"happy": {"all": 3}}, penalty={"happy": {"all": -10}, "food": -3},
        choices=[
            {"label": "Pay for the bulk brew (60 gold)", "cost": {"gold": 60}, "outcome": "solve", "result": "A long night of boiling, and it works."},
            {"label": "Burn the bedding and stay out of the plaza", "cost": {"food": 2}, "outcome": "gamble", "chance": 0.55,
             "result": "It might be enough."},
            {"label": "Do nothing", "cost": {}, "outcome": "fail", "result": "You turn away."}]),
    "tainted_grain": dict(
        title="Tainted Grain", giver="hale", kind="matter", days=2, weight=1.5, min_jobs=1,
        text="Hale found black mould in the grain stores and does not know how far it has spread. Buy sound grain, burn it all, or hope it is only the one sack.",
        thanks="The stores are clean. Hale posts a guard on them.", fail_text="The mould was everywhere. Half the stores are lost.",
        reward={"happy": {"hale": 5}}, penalty={"food": -6, "happy": {"all": -5}},
        choices=[
            {"label": "Buy sound grain (30 gold)", "cost": {"gold": 30}, "outcome": "solve", "result": "Marlow finds a cart of sound grain, at a price."},
            {"label": "Burn what is left and go short", "cost": {"food": 4}, "outcome": "solve", "result": "It hurts, but nothing else is spoiled."},
            {"label": "Hope it is one sack", "cost": {}, "outcome": "gamble", "chance": 0.35, "result": "You wait and see."}]),
    "light_fingers": dict(
        title="Light Fingers", giver="marlow", kind="matter", days=2, weight=2.0,
        text="Marlow's cash box is twenty gold lighter and he is shouting about it. {suspect} was seen near the stall. He wants it settled.",
        thanks="Settled. Marlow stops shouting, mostly.", fail_text="The gold is gone and the stall is a sour place to stand.",
        reward={"happy": {"marlow": 3}}, penalty={"gold": -20, "happy": {"marlow": -6}},
        choices=[
            {"label": "Search the stalls quietly (10 gold)", "cost": {"gold": 10}, "outcome": "gamble", "chance": 0.7,
             "result": "You check every corner."},
            {"label": "Accuse {suspect}", "cost": {}, "outcome": "gamble", "chance": 0.5, "result": "You point the finger.",
             "penalty": {"happy": {"{suspect}": -8, "marlow": -2}, "gold": -20}},
            {"label": "Tell Marlow to let it go", "cost": {}, "outcome": "fail", "result": "Marlow stares at you."}]),
    "peddler": dict(
        title="A Peddler at the Gate", giver="marlow", kind="matter", days=1, weight=1.5,
        text="A peddler has stopped at the gate with a cart. Marlow is already eyeing it. Rumour says the best of it is in the false bottom.",
        thanks="A good trade.", fail_text="The peddler moved on.",
        reward={"happy": {"marlow": 2}}, penalty={},
        choices=[
            {"label": "Buy the false-bottom bundle (60 gold)", "cost": {"gold": 60}, "outcome": "solve", "result": "Something wrapped in oilcloth.",
             "reward": {"item": 1, "happy": {"marlow": 2}}},
            {"label": "Buy bread and salt (10 gold)", "cost": {"gold": 10}, "outcome": "solve", "result": "Plain and welcome.",
             "reward": {"food": 3}},
            {"label": "Send him on", "cost": {}, "outcome": "fail", "result": "He tips his hat and goes."}]),
    "stall_trouble": dict(
        title="Trouble at the Stall", giver="marlow", kind="matter", days=2, weight=1.5,
        text="Marlow and Cutter are at each other's throats over a dice game. Settle it before it turns into a brawl.",
        thanks="They are not friends, but they are not fighting.", fail_text="It ended in a brawl and neither will say who started it.",
        reward={"relation": [["marlow", "cutter", 12]], "happy": {"marlow": 2, "cutter": 2}},
        penalty={"relation": [["marlow", "cutter", -10]], "happy": {"marlow": -8, "cutter": -8}},
        choices=[
            {"label": "Pay their stake and end the game (10 gold)", "cost": {"gold": 10}, "outcome": "solve", "result": "Neither wins. Both grumble."},
            {"label": "Take Marlow's side", "cost": {}, "outcome": "solve", "result": "Cutter will not forget it.",
             "reward": {"relation": [["marlow", "cutter", -6]], "happy": {"marlow": 5, "cutter": -6}}},
            {"label": "Stay out of it", "cost": {}, "outcome": "fail", "result": "You walk past."}]),
    # --- The whole world changes ---------------------------------------------------------------------------------------------------
    "blood_moon": dict(
        title="The Moon Turns Red", giver="", kind="world", weight=0.8, min_jobs=1,
        text="The moon rose red tonight. The old folk say the dead are bolder and the road pays better for it.",
        thanks="", fail_text="",
        reward={}, penalty={}, world_mod={"gold_mult": 2.0, "drop_mult": 1.5, "health_mult": 1.25, "days": 3}),
    "raging_hordes": dict(
        title="The Dead Are Restless", giver="", kind="world", weight=0.7, min_jobs=1,
        text="Word from the carters: the dead are thick on the road tonight, but thin and clumsy. A good time for a strong arm.",
        reward={}, penalty={}, world_mod={"count_mult": 1.5, "health_mult": 0.8, "days": 3}),
    "dangerous_dead": dict(
        title="Fewer, Worse", giver="", kind="world", weight=0.7, min_jobs=2,
        text="The scouts say there are fewer of them on the road now, and the ones left are bigger and meaner. Be careful.",
        reward={}, penalty={}, world_mod={"count_mult": 0.7, "health_mult": 1.35, "speed_mult": 1.05, "gold_mult": 1.3, "days": 3}),
    "fog_bank": dict(
        title="A Fog Bank", giver="", kind="world", weight=0.8,
        text="A fog bank has rolled in off the marsh and will sit on the road for a couple of days. You will not see far.",
        reward={}, penalty={}, world_mod={"ambient_mult": 0.75, "fog_mult": 2.2, "gold_mult": 1.15, "days": 2}),
    "vulnerable_town": dict(
        title="The Walls Are Thin", giver="", kind="world", weight=0.6, min_jobs=1,
        text="Something took down a stretch of the palisade in the night. Everyone is jumpy until it is mended, and the clan eats more.",
        reward={}, penalty={}, world_mod={"happy_per_day": -2.0, "food_per_day": -1, "days": 3}),
    "fat_harvest": dict(
        title="A Fat Harvest", giver="", kind="world", weight=0.7,
        text="The late fields came in better than anyone hoped. For a few days the granary fills and the mood lifts.",
        reward={}, penalty={}, world_mod={"happy_per_day": 2.0, "food_per_day": 2, "days": 3}),
    "plague_wells": dict(
        title="Plague in the Wells", giver="", kind="world", weight=0.5, min_jobs=2,
        text="Something has fouled the wells. Folk are wan and short-tempered, and the healer is worried.",
        reward={}, penalty={}, world_mod={"happy_per_day": -3.0, "days": 2}, links={"start": [link("fever", 0.5)]}),
}


def fmt(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return '"%s"' % v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, int):
        return str(v)
    if isinstance(v, (list, tuple)):
        if len(v) == 2 and all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in v) and False:
            return "Vector2(%s, %s)" % (repr(float(v[0])), repr(float(v[1])))
        return "[%s]" % ", ".join(fmt(x) for x in v)
    if isinstance(v, dict):
        if not v:
            return "{}"
        return "{\n%s\n}" % ",\n".join("%s: %s" % (fmt(k), fmt(x)) for k, x in v.items())
    raise TypeError(v)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    keep = {"%s.tres" % q for q in QUESTS}
    for old in OUT.glob("*.tres"):
        if old.name not in keep:
            old.unlink()
    defaults = dict(giver="hale", kind="kill_group", weight=1.0, min_jobs=0, days=0, target="", count=1, unique_name="",
                    unique_hp=3.0, unique_level=1.3, zone=[60, 200], item_name="", reward={}, penalty={}, choices=[], links={},
                    world_mod={}, text="", thanks="", fail_text="")
    for qid, q in QUESTS.items():
        d = {**defaults, **q}
        lines = ['[gd_resource type="Resource" script_class="QuestDef" load_steps=2 format=3]', "",
                 '[ext_resource type="Script" path="res://game/data/quest_def.gd" id="1"]', "", "[resource]",
                 'script = ExtResource("1")', 'id = "%s"' % qid]
        for key in ("title", "text", "thanks", "fail_text", "kind", "giver", "weight", "min_jobs", "days", "target", "count",
                    "unique_name", "unique_hp", "unique_level", "item_name", "reward", "penalty", "choices", "links", "world_mod"):
            value = d[key]
            if key in ("weight", "unique_hp", "unique_level"):
                value = float(value)
            lines.append("%s = %s" % (key, fmt(value)))
        lines.append("zone = Vector2(%s, %s)" % (repr(float(d["zone"][0])), repr(float(d["zone"][1]))))
        (OUT / ("%s.tres" % qid)).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print("wrote", len(QUESTS), "quests")


if __name__ == "__main__":
    main()
