#!/usr/bin/env python3
"""Writes the town's data: res://data/npcs/*.tres (NpcDef), res://data/traits/*.tres (TraitDef) and
res://data/modifiers/*.tres (RunModifierDef). Edit the tables and re-run; the .tres files are what the game loads.

Design notes are in docs/zombasite-world-and-npcs.md (sections 3 and 6)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "data"

# --- Personality traits: activity weights and what the NPC likes / dislikes others doing to them -----------------------------
TRAITS = {
    "gossip": dict(display_name="Gossip", weights={"gossip": 4.0}, likes=["gossip"], dislikes=[]),
    "argumentative": dict(display_name="Argumentative", weights={"argue": 3.5}, likes=["argue"], dislikes=["praise"]),
    "drunk": dict(display_name="Drunk", weights={"drink": 5.0}, likes=["joke"], dislikes=["pray"], excludes=["sober"]),
    "sober": dict(display_name="Sober", weights={"drink": 0.05}, likes=["pray"], dislikes=["joke"], excludes=["drunk"]),
    "generous": dict(display_name="Generous", weights={"praise": 3.0}, likes=["praise", "small_talk"], dislikes=["argue"]),
    "religious": dict(display_name="Religious", weights={"pray": 4.0}, likes=["praise", "pray"], dislikes=["joke"]),
    "joker": dict(display_name="Joker", weights={"joke": 3.5}, likes=["joke"], dislikes=["pray"]),
    "loyal": dict(display_name="Loyal", weights={"small_talk": 2.0, "work": 1.5}, likes=["small_talk", "praise"], dislikes=["gossip"]),
    "gloomy": dict(display_name="Gloomy", weights={"brood": 3.5}, likes=[], dislikes=["joke", "praise"]),
}

# --- The townspeople -----------------------------------------------------------------------------------------------------
NPCS = {
    "marlow": dict(display_name="Marlow", title="Trader", role="vendor", model_path="res://assets/models/npc_vendor", height=1.7,
                   home=(-8.0, -3.0), traits=["gossip", "drunk"], start_happiness=15.0,
                   lines={
                       "greet": ["Coin first, questions after.", "Gold's gold. Even now.", "Take a look. Don't touch the good stuff."],
                       "idle": ["Prices are only going up.", "Who's buying a sword in a town like this?", "Dry as dust, this job."],
                       "return_ok": ["You're back, and carrying coin. Good.", "Still breathing? Pleasure doing business."],
                       "return_dead": ["Left your gear on a corpse, did you?"],
                       "gossip": ["Heard the warden's been counting the grain twice a day.", "Between us? That mercenary is trouble."],
                       "argue": ["You watered it down again, didn't you?"], "praise": ["Honest work, that."],
                       "joke": ["Two zombies walk into a tavern. Short joke, that."], "small_talk": ["Quiet night."],
                   }),
    "hale": dict(display_name="Warden Hale", title="Keeper of the Board", role="keeper", model_path="res://assets/models/npc_keeper", height=1.7,
                 home=(8.0, -5.0), traits=["loyal", "argumentative"], start_happiness=20.0,
                 lines={
                     "greet": ["There's work on the board. Not much of it pays.", "Read it twice before you sign."],
                     "idle": ["Count the grain. Count the guards. Count the days.", "Another name struck off the list."],
                     "return_ok": ["The board's been paid. Well done.", "Good. The town owes you."],
                     "return_dead": ["I'll cross you off the list. Again."],
                     "gossip": ["The grain's lower than I'm saying."], "argue": ["That is not how it is written."],
                     "praise": ["Steady hands, that one."], "joke": ["Don't."], "small_talk": ["The walls hold, for now."],
                 }),
    "maren": dict(display_name="Old Maren", title="Healer", role="healer", model_path="res://assets/models/npc_healer", height=1.6,
                  home=(3.5, 1.0), traits=["religious", "generous"], start_happiness=25.0,
                  lines={
                      "greet": ["Sit. Let me see that wound.", "The stone's warm. Stand near it."],
                      "idle": ["Herbs run short every winter.", "Mind the stone, child."],
                      "return_ok": ["Back on your feet. Good.", "Bless you. And bleed less."],
                      "return_dead": ["Oh, child. Not again."],
                      "gossip": ["That trader waters his drink. And his wine."], "argue": ["Hmph."],
                      "praise": ["The light finds the faithful."], "joke": ["Wicked boy."], "small_talk": ["Cold wind tonight."],
                  }),
    "dorn": dict(display_name="Dorn", title="Smith", role="smith", model_path="res://assets/models/npc_smith", height=1.8,
                 home=(-15.8, -9.6), traits=["loyal", "gloomy"], start_happiness=12.0,
                 lines={
                     "greet": ["Steel doesn't care who carries it. Buy what you can swing.", "Mind the sparks."],
                     "idle": ["Good iron's scarcer than good men.", "The forge never goes cold. Neither does my back.", "Can't beat a blade into shape in a hurry."],
                     "return_ok": ["That edge held? Good.", "Back with all your fingers. Impressive."],
                     "return_dead": ["I'll scrape what's left of your sword off the anvil."],
                     "gossip": ["The trader sells scrap and swears it's steel."], "argue": ["You'd never last a day at the bellows."],
                     "praise": ["You hold your ground. That counts."], "joke": ["A sword walks into a bar. Gets sheathed."],
                     "small_talk": ["Cold for forging weather."], "work": ["Back to the anvil."],
                 }),
    "cutter": dict(display_name="Cutter", title="Sellsword", role="recruit", model_path="res://assets/models/npc_recruit", height=1.8,
                   home=(11.0, 5.0), traits=["argumentative", "joker"], start_happiness=10.0, recruit_cost=60, clan_skill="forager",
                   lines={
                       "greet": ["You look like you could use another blade.", "Sixty coin and I stop standing around."],
                       "idle": ["Sharpened it twice today. Nothing to cut.", "I've slept in worse places."],
                       "hire": ["Done. I forage as well as I fight. Mostly."],
                       "return_ok": ["Still alive. Nice."], "return_dead": ["Told you to pay me up front."],
                       "gossip": ["The old woman talks to the stone."], "argue": ["Say that again."],
                       "praise": ["Not bad."], "joke": ["A priest, a ghoul and a barmaid..."], "small_talk": ["Quiet out there."],
                   }),
}

# --- Run modifiers: the rules a run plays by --------------------------------------------------------------------
MODIFIERS = {
    "swarming": dict(display_name="Swarming", description="More of the small and fast. Fewer pieces of cover.",
                     spawn_weights={"zombie": 1.7, "ghoul": 1.8}, health_mult=0.9, reward_mult=1.15),
    "nest": dict(display_name="Spitters' Nest", description="The air is thick with spit and rot.",
                 spawn_weights={"spitter": 3.0, "bloater": 1.6}, reward_mult=1.1, min_stage=2),
    "gigantism": dict(display_name="Gigantism", description="Everything is bigger, slower and harder to put down.",
                      size_mult=1.25, health_mult=1.5, speed_mult=0.92, reward_mult=1.25),
    "fleet": dict(display_name="Fleet of Foot", description="They do not tire.", speed_mult=1.25, reward_mult=1.15),
    "darkness": dict(display_name="Darkness", description="The moon is hidden. You will hear them first.",
                     ambient_mult=0.45, fog_mult=1.4, reward_mult=1.2, excludes=["moonlit"]),
    "moonlit": dict(display_name="Moonlit", description="A clear, cold night. Easier to see, easier to be seen.",
                    ambient_mult=1.35, fog_mult=0.6, reward_mult=0.9, excludes=["darkness", "fog"]),
    "fog": dict(display_name="Fog", description="A thick grey fog hides the pack until it is on you.",
                fog_mult=3.2, ambient_mult=0.8, reward_mult=1.1, excludes=["moonlit"]),
    "cursed": dict(display_name="Cursed", description="The priests are many and the dead rise twice.",
                   spawn_weights={"priest": 3.0, "brute": 1.4}, reward_mult=1.3, min_stage=2),
    "brutal": dict(display_name="Brutal", description="Brutes, and plenty of them.",
                   spawn_weights={"brute": 2.5}, health_mult=1.15, reward_mult=1.3, min_stage=2),
}


def fmt(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return '"%s"' % v.replace("\\", "\\\\").replace('"', '\\"')
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, int):
        return str(v)
    if isinstance(v, tuple) and len(v) == 2:
        return "Vector2(%s, %s)" % tuple(repr(float(x)) for x in v)
    if isinstance(v, list):
        return "[%s]" % ", ".join(fmt(x) for x in v)
    if isinstance(v, dict):
        if not v:
            return "{}"
        return "{\n%s\n}" % ",\n".join("%s: %s" % (fmt(k), fmt(x)) for k, x in v.items())
    raise TypeError(v)


def typed_strings(items) -> str:
    return "Array[String]([%s])" % ", ".join('"%s"' % x for x in items)


def write(folder: str, script: str, class_name: str, ident: str, fields: list) -> None:
    out = ROOT / folder
    out.mkdir(parents=True, exist_ok=True)
    lines = [
        '[gd_resource type="Resource" script_class="%s" load_steps=2 format=3]' % class_name, "",
        '[ext_resource type="Script" path="res://game/data/%s" id="1"]' % script, "", "[resource]",
        'script = ExtResource("1")', 'id = "%s"' % ident,
    ]
    lines += ["%s = %s" % kv for kv in fields]
    (out / ("%s.tres" % ident)).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print("wrote", folder, ident)


def main() -> None:
    for tid, t in TRAITS.items():
        write("traits", "trait_def.gd", "TraitDef", tid, [
            ("display_name", fmt(t["display_name"])), ("weights", fmt(t["weights"])), ("likes", typed_strings(t["likes"])),
            ("dislikes", typed_strings(t["dislikes"])), ("excludes", typed_strings(t.get("excludes", [])))])
    for nid, n in NPCS.items():
        write("npcs", "npc_def.gd", "NpcDef", nid, [
            ("display_name", fmt(n["display_name"])), ("role", fmt(n["role"])), ("title", fmt(n["title"])),
            ("model_path", fmt(n["model_path"])), ("height", fmt(float(n["height"]))), ("home", fmt(n["home"])),
            ("traits", typed_strings(n["traits"])), ("start_happiness", fmt(float(n["start_happiness"]))),
            ("recruit_cost", fmt(n.get("recruit_cost", 0))), ("clan_skill", fmt(n.get("clan_skill", ""))),
            ("lines", fmt(n["lines"]))])
    for mid, m in MODIFIERS.items():
        write("modifiers", "run_modifier_def.gd", "RunModifierDef", mid, [
            ("display_name", fmt(m["display_name"])), ("description", fmt(m["description"])),
            ("spawn_weights", fmt(m.get("spawn_weights", {}))), ("count_mult", fmt(float(m.get("count_mult", 1.0)))),
            ("health_mult", fmt(float(m.get("health_mult", 1.0)))), ("speed_mult", fmt(float(m.get("speed_mult", 1.0)))),
            ("size_mult", fmt(float(m.get("size_mult", 1.0)))), ("ambient_mult", fmt(float(m.get("ambient_mult", 1.0)))),
            ("fog_mult", fmt(float(m.get("fog_mult", 1.0)))), ("reward_mult", fmt(float(m.get("reward_mult", 1.0)))),
            ("min_stage", fmt(int(m.get("min_stage", 1)))), ("excludes", typed_strings(m.get("excludes", [])))])


if __name__ == "__main__":
    main()
