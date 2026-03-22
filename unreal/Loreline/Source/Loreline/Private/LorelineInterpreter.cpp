#include "LorelineInterpreter.h"
#include "LorelineModule.h"
#include "Loreline.h"

void ULorelineInterpreter::BeginDestroy()
{
	if (NativeInterpreter)
	{
		Loreline_releaseInterpreter(NativeInterpreter);
		NativeInterpreter = nullptr;
	}
	PendingAdvance = nullptr;
	PendingSelect = nullptr;
	Super::BeginDestroy();
}

// --- Native callback bridge ---

void ULorelineInterpreter::OnDialogueCallback(
	Loreline_Interpreter* Interp,
	Loreline_String Character,
	Loreline_String Text,
	const Loreline_TextTag* Tags,
	int TagCount,
	void (*AdvanceFn)(void),
	void* UserData)
{
	ULorelineInterpreter* Self = static_cast<ULorelineInterpreter*>(UserData);
	Self->PendingAdvance = AdvanceFn;
	Self->PendingSelect = nullptr;

	FString CharStr = Character.isNull() ? FString() : UTF8_TO_TCHAR(Character.c_str());
	FString TextStr = Text.isNull() ? FString() : UTF8_TO_TCHAR(Text.c_str());
	TArray<FLorelineTextTag> TagArray = ConvertTags(Tags, TagCount);

	Self->OnDialogue.Broadcast(CharStr, TextStr, TagArray);
}

void ULorelineInterpreter::OnChoiceCallback(
	Loreline_Interpreter* Interp,
	const Loreline_ChoiceOption* Options,
	int OptionCount,
	void (*SelectFn)(int),
	void* UserData)
{
	ULorelineInterpreter* Self = static_cast<ULorelineInterpreter*>(UserData);
	Self->PendingSelect = SelectFn;
	Self->PendingAdvance = nullptr;

	TArray<FLorelineChoiceOption> OptionArray = ConvertOptions(Options, OptionCount);

	Self->OnChoice.Broadcast(OptionArray);
}

void ULorelineInterpreter::OnFinishCallback(
	Loreline_Interpreter* Interp,
	void* UserData)
{
	ULorelineInterpreter* Self = static_cast<ULorelineInterpreter*>(UserData);
	Self->PendingAdvance = nullptr;
	Self->PendingSelect = nullptr;

	Self->OnFinished.Broadcast();
}

// --- Conversion helpers ---

TArray<FLorelineTextTag> ULorelineInterpreter::ConvertTags(const Loreline_TextTag* Tags, int TagCount)
{
	TArray<FLorelineTextTag> Result;
	Result.Reserve(TagCount);
	for (int i = 0; i < TagCount; i++)
	{
		FLorelineTextTag Tag;
		Tag.Value = UTF8_TO_TCHAR(Tags[i].value.c_str());
		Tag.Offset = Tags[i].offset;
		Tag.bClosing = Tags[i].closing;
		Result.Add(Tag);
	}
	return Result;
}

TArray<FLorelineChoiceOption> ULorelineInterpreter::ConvertOptions(const Loreline_ChoiceOption* Options, int OptionCount)
{
	TArray<FLorelineChoiceOption> Result;
	Result.Reserve(OptionCount);
	for (int i = 0; i < OptionCount; i++)
	{
		FLorelineChoiceOption Option;
		Option.Text = UTF8_TO_TCHAR(Options[i].text.c_str());
		Option.bEnabled = Options[i].enabled;
		Option.Tags = ConvertTags(Options[i].tags, Options[i].tagCount);
		Result.Add(Option);
	}
	return Result;
}

FLorelineValue ULorelineInterpreter::NativeToValue(const Loreline_Value& Value)
{
	switch (Value.type)
	{
	case Loreline_Int:         return FLorelineValue::MakeInt(Value.intValue);
	case Loreline_Float:       return FLorelineValue::MakeFloat(Value.floatValue);
	case Loreline_Bool:        return FLorelineValue::MakeBool(Value.boolValue);
	case Loreline_StringValue: return FLorelineValue::MakeString(UTF8_TO_TCHAR(Value.stringValue.c_str()));
	default:                   return FLorelineValue::MakeNull();
	}
}

Loreline_Value ULorelineInterpreter::ValueToNative(const FLorelineValue& Value)
{
	switch (Value.Type)
	{
	case ELorelineValueType::Int:    return Loreline_Value::from_int(Value.IntValue);
	case ELorelineValueType::Float:  return Loreline_Value::from_float(Value.FloatValue);
	case ELorelineValueType::Bool:   return Loreline_Value::from_bool(Value.BoolValue);
	case ELorelineValueType::String: return Loreline_Value::from_string(Loreline_String(TCHAR_TO_UTF8(*Value.StringValue)));
	default:                         return Loreline_Value::null_val();
	}
}

// --- Public methods ---

void ULorelineInterpreter::Advance()
{
	if (PendingAdvance)
	{
		auto Fn = PendingAdvance;
		PendingAdvance = nullptr;
		Fn();
	}
}

void ULorelineInterpreter::Select(int32 Index)
{
	if (PendingSelect)
	{
		auto Fn = PendingSelect;
		PendingSelect = nullptr;
		Fn(Index);
	}
}

void ULorelineInterpreter::Start(const FString& BeatName)
{
	if (!NativeInterpreter) return;
	Loreline_start(NativeInterpreter, Loreline_String(TCHAR_TO_UTF8(*BeatName)));
}

FString ULorelineInterpreter::SaveState() const
{
	if (!NativeInterpreter) return FString();
	Loreline_String Result = Loreline_save(NativeInterpreter);
	return Result.isNull() ? FString() : UTF8_TO_TCHAR(Result.c_str());
}

void ULorelineInterpreter::RestoreState(const FString& SaveData)
{
	if (!NativeInterpreter) return;
	Loreline_restore(NativeInterpreter, Loreline_String(TCHAR_TO_UTF8(*SaveData)));
}

FLorelineValue ULorelineInterpreter::GetCharacterField(const FString& Character, const FString& Field) const
{
	if (!NativeInterpreter) return FLorelineValue::MakeNull();
	Loreline_Value Val = Loreline_getCharacterField(
		NativeInterpreter,
		Loreline_String(TCHAR_TO_UTF8(*Character)),
		Loreline_String(TCHAR_TO_UTF8(*Field)));
	return NativeToValue(Val);
}

void ULorelineInterpreter::SetCharacterField(const FString& Character, const FString& Field, const FLorelineValue& Value)
{
	if (!NativeInterpreter) return;
	Loreline_setCharacterField(
		NativeInterpreter,
		Loreline_String(TCHAR_TO_UTF8(*Character)),
		Loreline_String(TCHAR_TO_UTF8(*Field)),
		ValueToNative(Value));
}

FLorelineValue ULorelineInterpreter::GetStateField(const FString& Field) const
{
	if (!NativeInterpreter) return FLorelineValue::MakeNull();
	Loreline_Value Val = Loreline_getStateField(
		NativeInterpreter,
		Loreline_String(TCHAR_TO_UTF8(*Field)));
	return NativeToValue(Val);
}

void ULorelineInterpreter::SetStateField(const FString& Field, const FLorelineValue& Value)
{
	if (!NativeInterpreter) return;
	Loreline_setStateField(
		NativeInterpreter,
		Loreline_String(TCHAR_TO_UTF8(*Field)),
		ValueToNative(Value));
}

FLorelineValue ULorelineInterpreter::GetTopLevelStateField(const FString& Field) const
{
	if (!NativeInterpreter) return FLorelineValue::MakeNull();
	Loreline_Value Val = Loreline_getTopLevelStateField(
		NativeInterpreter,
		Loreline_String(TCHAR_TO_UTF8(*Field)));
	return NativeToValue(Val);
}

void ULorelineInterpreter::SetTopLevelStateField(const FString& Field, const FLorelineValue& Value)
{
	if (!NativeInterpreter) return;
	Loreline_setTopLevelStateField(
		NativeInterpreter,
		Loreline_String(TCHAR_TO_UTF8(*Field)),
		ValueToNative(Value));
}

FLorelineNodeInfo ULorelineInterpreter::CurrentNode() const
{
	FLorelineNodeInfo Info;
	if (!NativeInterpreter) return Info;

	Loreline_Node Node = Loreline_currentNode(NativeInterpreter);
	if (Node.type.isNull()) return Info;

	Info.Type = UTF8_TO_TCHAR(Node.type.c_str());
	Info.Line = Node.line;
	Info.Column = Node.column;
	Info.Offset = Node.offset;
	Info.Length = Node.length;
	return Info;
}
