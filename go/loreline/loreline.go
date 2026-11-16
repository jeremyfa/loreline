package loreline

import (
	"errors"
	"os"

	"github.com/mikaib/loreline/go/loreline/internal/core"
)

var library *core.Hx_Obj_loreline_lib_golibrary

func init() {
	library = core.Hx_Obj_loreline_lib_golibrary_CreateInstance()
}

type TextTag struct {
	Value   string
	Offset  int
	Closing bool
}

type ChoiceOption struct {
	Text    string
	Tags    []TextTag
	Enabled bool
}

type DialogueHandler func(it *Interpreter, character string, text string, tags []TextTag, advance func())

type ChoiceHandler func(it *Interpreter, options []ChoiceOption, choose func(index int))

type FinishHandler func(it *Interpreter)

type ErrorHandler func(it *Interpreter, err error)

type Function func(it *Interpreter, args []any) any

type FileReader func(path string) (string, bool)

type Handlers struct {
	Dialogue DialogueHandler
	Choice   ChoiceHandler
	Finish   FinishHandler
	Error    ErrorHandler
}

type Options struct {
	Beat         string
	Functions    map[string]Function
	StrictAccess bool
	Translations *Translations
}

type Node struct {
	node *core.Hx_Obj_loreline_lib_gonode
}

type Script struct {
	Node
	script *core.Hx_Obj_loreline_lib_goscript
}

type Translations struct {
	translations *core.Hx_Obj_loreline_lib_gotranslations
}

type Interpreter struct {
	interp  *core.Hx_Obj_loreline_lib_gointerpreter
	onError ErrorHandler
	err     error
}

var (
	syncDepth int
	syncErr   error
)

func Parse(source string) (*Script, error) {
	return ParseWithImports(source, "", nil)
}

func ParseFile(path string) (*Script, error) {
	source, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	return ParseWithImports(string(source), path, ReadFile)
}

func ReadFile(path string) (string, bool) {
	data, err := os.ReadFile(path)
	return string(data), err == nil
}

func ParseWithImports(source string, path string, readFile FileReader) (*Script, error) {
	var s *core.Hx_Obj_loreline_lib_goscript
	err := run(func() (err error) {
		s, err = library.Parse(source, path, coreReader(readFile))
		return err
	})
	if err != nil {
		return nil, err
	}

	return newScript(s), nil
}

func ScriptFromJSON(json string) (*Script, error) {
	var s *core.Hx_Obj_loreline_lib_goscript
	err := run(func() (err error) {
		s, err = library.ScriptFromJson(json)
		return err
	})
	if err != nil {
		return nil, err
	}

	return newScript(s), nil
}

func NodeFromJSON(json string) (*Node, error) {
	var n *core.Hx_Obj_loreline_lib_gonode
	err := run(func() (err error) {
		n, err = library.NodeFromJson(json)
		return err
	})
	if err != nil {
		return nil, err
	}

	return &Node{node: n}, nil
}

func ExtractTranslations(script *Script) *Translations {
	return &Translations{translations: library.ExtractTranslations(script.script)}
}

func LoadLocale(locale string, script *Script, path string, readFile FileReader) (*Translations, error) {
	if readFile == nil {
		readFile = ReadFile
	}

	var t *core.Hx_Obj_loreline_lib_gotranslations
	err := run(func() (err error) {
		t, err = library.LoadLocale(locale, script.script, path, coreReader(readFile))
		return err
	})
	if err != nil {
		return nil, err
	}

	return &Translations{translations: t}, nil
}

func TranslationFormat(name string, enabled bool) {
	library.TranslationFormat(name, enabled)
}

func Update(delta float64) {
	run(func() error {
		library.Update(delta)
		return nil
	})
}

func (n *Node) Type() string {
	return n.node.Type()
}

func (n *Node) Line() int {
	return int(n.node.Line())
}

func (n *Node) Column() int {
	return int(n.node.Column())
}

func (n *Node) Offset() int {
	return int(n.node.Offset())
}

func (n *Node) Length() int {
	return int(n.node.Length())
}

func (n *Node) ID() string {
	return n.node.Id()
}

func (n *Node) ToJSON(pretty bool) string {
	return n.node.ToJson(pretty)
}

func (s *Script) Play(handlers Handlers, options *Options) (*Interpreter, error) {
	var interp *core.Hx_Obj_loreline_lib_gointerpreter
	dialogue, choice, finish := bridges(handlers, true)
	err := run(func() (err error) {
		interp, err = s.script.Play(dialogue, choice, finish, beatOf(options), coreOptions(options))
		return err
	})
	return started(interp, handlers, err)
}

func (s *Script) Resume(handlers Handlers, save string, options *Options) (*Interpreter, error) {
	var interp *core.Hx_Obj_loreline_lib_gointerpreter
	dialogue, choice, finish := bridges(handlers, true)
	err := run(func() (err error) {
		interp, err = s.script.Resume(dialogue, choice, finish, save, beatOf(options), coreOptions(options))
		return err
	})
	return started(interp, handlers, err)
}

func (s *Script) Print(indent string, newline string) string {
	return s.script.Print(indent, newline)
}

func (s *Script) Format() string {
	return s.Print("  ", "\n")
}

func (it *Interpreter) Err() error {
	return it.err
}

func (it *Interpreter) Start(beat string) error {
	return run(func() error {
		return it.interp.Start(beat)
	})
}

func (it *Interpreter) Save() (string, error) {
	var save string
	err := run(func() (err error) {
		save, err = it.interp.Save()
		return err
	})
	return save, err
}

func (it *Interpreter) Restore(save string) error {
	return run(func() error {
		return it.interp.Restore(save)
	})
}

func (it *Interpreter) Resume() error {
	return run(func() error {
		return it.interp.Resume()
	})
}

func (it *Interpreter) Key() string {
	return it.interp.Key()
}

func (it *Interpreter) IsRoot() bool {
	return it.interp.IsRoot()
}

func (it *Interpreter) Spawn(key string, handlers Handlers) (*Interpreter, error) {
	var interp *core.Hx_Obj_loreline_lib_gointerpreter
	dialogue, choice, finish := bridges(handlers, false)
	err := run(func() (err error) {
		interp, err = it.interp.Spawn(key, dialogue, choice, finish)
		return err
	})
	return it.child(interp, handlers, err)
}

func (it *Interpreter) ResumeSpawn(key string, handlers Handlers) (*Interpreter, error) {
	var interp *core.Hx_Obj_loreline_lib_gointerpreter
	dialogue, choice, finish := bridges(handlers, false)
	err := run(func() (err error) {
		interp, err = it.interp.ResumeSpawn(key, dialogue, choice, finish)
		return err
	})
	return it.child(interp, handlers, err)
}

func (it *Interpreter) ResumableSpawnKeys() []string {
	keys := it.interp.ResumableSpawnKeys()
	result := make([]string, keys.Len())
	for i := range result {
		result[i] = keys.Get(int32(i))
	}
	return result
}

func (it *Interpreter) SeedRandom(seed float64) {
	it.interp.SeedRandom(seed)
}

func (it *Interpreter) SeedRandomFromClock() {
	it.interp.SeedRandomFromClock()
}

func (it *Interpreter) Dispose() error {
	return run(func() error {
		return it.interp.Dispose()
	})
}

func (it *Interpreter) Character(name string) map[string]any {
	fields, _ := fromHaxe(it.interp.Character(name)).(map[string]any)
	return fields
}

func (it *Interpreter) CharacterField(character string, name string) any {
	return fromHaxe(it.interp.CharacterField(character, name))
}

func (it *Interpreter) SetCharacterField(character string, name string, value any) {
	it.interp.SetCharacterField(character, name, toHaxe(value))
}

func (it *Interpreter) StateField(name string) any {
	return fromHaxe(it.interp.StateField(name))
}

func (it *Interpreter) SetStateField(name string, value any) {
	it.interp.SetStateField(name, toHaxe(value))
}

func (it *Interpreter) TopLevelStateField(name string) any {
	return fromHaxe(it.interp.TopLevelStateField(name))
}

func (it *Interpreter) SetTopLevelStateField(name string, value any) {
	it.interp.SetTopLevelStateField(name, toHaxe(value))
}

func (it *Interpreter) CurrentNode() *Node {
	node := it.interp.CurrentNode()
	if node == nil {
		return nil
	}
	return &Node{node: node}
}

func newScript(s *core.Hx_Obj_loreline_lib_goscript) *Script {
	return &Script{Node: Node{node: &s.Hx_Obj_loreline_lib_gonode}, script: s}
}

func started(interp *core.Hx_Obj_loreline_lib_gointerpreter, handlers Handlers, err error) (*Interpreter, error) {
	if err != nil {
		return nil, err
	}

	it := wrap(interp)
	it.onError = handlers.Error
	return it, nil
}

func (it *Interpreter) child(interp *core.Hx_Obj_loreline_lib_gointerpreter, handlers Handlers, err error) (*Interpreter, error) {
	if err != nil {
		return nil, err
	}

	child := wrap(interp)
	child.onError = handlers.Error
	if child.onError == nil {
		child.onError = it.onError
	}
	return child, nil
}

func wrap(interp *core.Hx_Obj_loreline_lib_gointerpreter) *Interpreter {
	if interp == nil {
		return nil
	}
	if it, ok := interp.Host().(*Interpreter); ok {
		return it
	}

	it := &Interpreter{interp: interp}
	interp.SetHost(it)
	return it
}

func run(call func() error) (err error) {
	syncDepth++
	defer func() {
		syncDepth--
		if r := recover(); r != nil {
			err = toError(r)
		}
		if err == nil && syncDepth == 0 {
			err = syncErr
		}
		if syncDepth == 0 {
			syncErr = nil
		}
	}()

	return call()
}

func (it *Interpreter) guard(call func()) {
	defer func() {
		if r := recover(); r != nil {
			err := toError(r)
			if syncDepth > 0 {
				if syncErr == nil {
					syncErr = err
				}
				return
			}
			it.err = err
			if it.onError != nil {
				it.onError(it, err)
			}
		}
	}()

	call()
}

func toError(value any) error {
	if err, ok := value.(error); ok {
		return err
	}
	return errors.New(library.ErrorMessage(value))
}

func bridges(handlers Handlers, root bool) (
	core.Hx_Typedef_loreline_lib_godialoguehandler,
	core.Hx_Typedef_loreline_lib_gochoicehandler,
	core.Hx_Typedef_loreline_lib_gofinishhandler,
) {
	var dialogue core.Hx_Typedef_loreline_lib_godialoguehandler
	if handlers.Dialogue != nil || root {
		dialogue = func(interp *core.Hx_Obj_loreline_lib_gointerpreter, character string, text string, tags core.HxArray[*core.Hx_Obj_loreline_texttag], advance func()) {
			it := wrap(interp)
			next := func() {
				it.guard(advance)
			}
			if handlers.Dialogue == nil {
				next()
				return
			}
			handlers.Dialogue(it, character, text, convertTags(tags), next)
		}
	}

	var choice core.Hx_Typedef_loreline_lib_gochoicehandler
	if handlers.Choice != nil || root {
		choice = func(interp *core.Hx_Obj_loreline_lib_gointerpreter, options core.HxArray[*core.Hx_Obj_loreline_choiceoption], choose func(int32)) {
			it := wrap(interp)
			converted := convertOptions(options)
			pick := func(index int) {
				it.guard(func() {
					choose(int32(index))
				})
			}
			if handlers.Choice == nil {
				for i, option := range converted {
					if option.Enabled {
						pick(i)
						return
					}
				}
				return
			}
			handlers.Choice(it, converted, pick)
		}
	}

	var finish core.Hx_Typedef_loreline_lib_gofinishhandler
	if handlers.Finish != nil || root {
		finish = func(interp *core.Hx_Obj_loreline_lib_gointerpreter) {
			if handlers.Finish != nil {
				handlers.Finish(wrap(interp))
			}
		}
	}

	return dialogue, choice, finish
}

func coreReader(readFile FileReader) func(string) string {
	if readFile == nil {
		return nil
	}

	return func(path string) string {
		data, ok := readFile(path)
		if !ok {
			return core.HxStringNull
		}
		return data
	}
}

func beatOf(options *Options) string {
	if options == nil {
		return ""
	}
	return options.Beat
}

func coreOptions(options *Options) *core.Hx_Obj_loreline_lib_gooptions {
	if options == nil {
		return nil
	}

	result := core.Hx_Obj_loreline_lib_gooptions_CreateInstance()
	for name, fn := range options.Functions {
		fn := fn
		result.AddFunction(name, func(interp *core.Hx_Obj_loreline_lib_gointerpreter, args core.HxArray[any]) any {
			values, _ := fromHaxe(args).([]any)
			return toHaxe(fn(wrap(interp), values))
		})
	}
	result.SetStrictAccess(options.StrictAccess)
	if options.Translations != nil {
		result.SetTranslations(options.Translations.translations)
	}
	return result
}

func convertTags(tags core.HxArray[*core.Hx_Obj_loreline_texttag]) []TextTag {
	if tags == nil {
		return []TextTag{}
	}

	converted := make([]TextTag, tags.Len())
	for i := range converted {
		tag := tags.Get(int32(i))
		converted[i] = TextTag{
			Value:   tag.Hx_Field_value,
			Offset:  int(tag.Hx_Field_offset),
			Closing: tag.Hx_Field_closing,
		}
	}
	return converted
}

func convertOptions(options core.HxArray[*core.Hx_Obj_loreline_choiceoption]) []ChoiceOption {
	converted := make([]ChoiceOption, options.Len())
	for i := range converted {
		option := options.Get(int32(i))
		converted[i] = ChoiceOption{
			Text:    option.Hx_Field_text,
			Tags:    convertTags(option.Hx_Field_tags),
			Enabled: option.Hx_Field_enabled,
		}
	}
	return converted
}

func fromHaxe(value any) any {
	switch v := value.(type) {
	case nil:
		return nil
	case string:
		if v == core.HxStringNull {
			return nil
		}
		return v
	case int32:
		return int(v)
	case map[string]any:
		converted := make(map[string]any, len(v))
		for key, item := range v {
			converted[key] = fromHaxe(item)
		}
		return converted
	case interface{ Dyn() core.HxArray[any] }:
		items := v.Dyn()
		converted := make([]any, items.Len())
		for i := range converted {
			converted[i] = fromHaxe(items.Get(int32(i)))
		}
		return converted
	default:
		return value
	}
}

func toHaxe(value any) any {
	switch v := value.(type) {
	case nil:
		return nil
	case int:
		return int32(v)
	case int64:
		return int32(v)
	case float32:
		return float64(v)
	case []any:
		items := make([]any, len(v))
		for i, item := range v {
			items[i] = toHaxe(item)
		}
		return core.HxMakeArray[any](items...)
	case []string:
		items := make([]any, len(v))
		for i, item := range v {
			items[i] = item
		}
		return core.HxMakeArray[any](items...)
	case map[string]any:
		converted := make(map[string]any, len(v))
		for key, item := range v {
			converted[key] = toHaxe(item)
		}
		return converted
	default:
		return value
	}
}
