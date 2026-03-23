#include "register_types.h"

#include "loreline_runtime.h"
#include "loreline_script.h"
#include "loreline_interpreter.h"
#include "loreline_options.h"
#include "loreline_resource_loader.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/classes/resource_loader.hpp>

using namespace godot;

static Ref<LorelineResourceLoader> lor_loader;

void initialize_loreline_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(Loreline);
	GDREGISTER_CLASS(LorelineScript);
	GDREGISTER_CLASS(LorelineInterpreter);
	GDREGISTER_CLASS(LorelineOptions);
	GDREGISTER_CLASS(LorelineResourceLoader);

	lor_loader.instantiate();
	ResourceLoader::get_singleton()->add_resource_format_loader(lor_loader);
}

void uninitialize_loreline_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	if (lor_loader.is_valid()) {
		ResourceLoader::get_singleton()->remove_resource_format_loader(lor_loader);
		lor_loader.unref();
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT loreline_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(
			p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_loreline_module);
	init_obj.register_terminator(uninitialize_loreline_module);
	init_obj.set_minimum_library_initialization_level(
			MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
}
