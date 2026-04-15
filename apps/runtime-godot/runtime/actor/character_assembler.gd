extends RefCounted
class_name CharacterAssembler


func assemble(actor_definition: Resource) -> Dictionary:
	if actor_definition == null:
		return {}
	var runtime_bundle := {
		"actor_id": actor_definition.actor_id,
		"semantic_defaults": actor_definition.semantic_defaults.duplicate(),
		"clips": actor_definition.clips.duplicate(),
		"movement_profile": actor_definition.movement_profile.duplicate(),
		"metadata": actor_definition.metadata.duplicate(),
	}
	return runtime_bundle
