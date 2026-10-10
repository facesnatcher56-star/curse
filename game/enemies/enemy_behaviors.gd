class_name EnemyBehaviors
extends RefCounted
## Maps an EnemyDef.behavior name to its EnemyBehavior class. Add a line here when a new behaviour is written.

static func create(id: String) -> EnemyBehavior:
	match id:
		"warden":
			return WardenBehavior.new()
		"pouncer":
			return PouncerBehavior.new()
		"spitter":
			return SpitterBehavior.new()
		"bloater":
			return BloaterBehavior.new()
		"support":
			return SupportBehavior.new()
		_:
			return MeleeBehavior.new()
