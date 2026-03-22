#include "LorelineScript.h"
#include "LorelineInterpreter.h"
#include "LorelineModule.h"
#include "Loreline.h"

void ULorelineScript::BeginDestroy()
{
	if (NativeScript)
	{
		Loreline_releaseScript(NativeScript);
		NativeScript = nullptr;
	}
	Super::BeginDestroy();
}

ULorelineInterpreter* ULorelineScript::Play(const FString& BeatName)
{
	if (!NativeScript)
	{
		UE_LOG(LogLoreline, Error, TEXT("Loreline: Cannot play - script is null"));
		return nullptr;
	}

	ULorelineInterpreter* Interp = NewObject<ULorelineInterpreter>(this);

	Loreline_Interpreter* NativeInterp = Loreline_play(
		NativeScript,
		&ULorelineInterpreter::OnDialogueCallback,
		&ULorelineInterpreter::OnChoiceCallback,
		&ULorelineInterpreter::OnFinishCallback,
		Loreline_String(TCHAR_TO_UTF8(*BeatName)),
		nullptr, // translations
		Interp   // userData
	);

	if (!NativeInterp)
	{
		UE_LOG(LogLoreline, Error, TEXT("Loreline: Failed to create interpreter"));
		return nullptr;
	}

	Interp->SetNativeInterpreter(NativeInterp);
	return Interp;
}

ULorelineInterpreter* ULorelineScript::Resume(const FString& SaveData, const FString& BeatName)
{
	if (!NativeScript)
	{
		UE_LOG(LogLoreline, Error, TEXT("Loreline: Cannot resume - script is null"));
		return nullptr;
	}

	ULorelineInterpreter* Interp = NewObject<ULorelineInterpreter>(this);

	Loreline_Interpreter* NativeInterp = Loreline_resume(
		NativeScript,
		&ULorelineInterpreter::OnDialogueCallback,
		&ULorelineInterpreter::OnChoiceCallback,
		&ULorelineInterpreter::OnFinishCallback,
		Loreline_String(TCHAR_TO_UTF8(*SaveData)),
		Loreline_String(TCHAR_TO_UTF8(*BeatName)),
		nullptr, // translations
		Interp   // userData
	);

	if (!NativeInterp)
	{
		UE_LOG(LogLoreline, Error, TEXT("Loreline: Failed to resume interpreter"));
		return nullptr;
	}

	Interp->SetNativeInterpreter(NativeInterp);
	return Interp;
}

FString ULorelineScript::ToJson(bool bPretty) const
{
	if (!NativeScript) return FString();
	Loreline_String Json = Loreline_scriptToJson(NativeScript, bPretty);
	return Json.isNull() ? FString() : UTF8_TO_TCHAR(Json.c_str());
}

ULorelineScript* ULorelineScript::FromJson(UObject* WorldContext, const FString& Json)
{
	Loreline_Script* NativeScript = Loreline_scriptFromJson(
		Loreline_String(TCHAR_TO_UTF8(*Json)));

	if (!NativeScript)
	{
		UE_LOG(LogLoreline, Error, TEXT("Loreline: Failed to parse script from JSON"));
		return nullptr;
	}

	ULorelineScript* Script = NewObject<ULorelineScript>(WorldContext);
	Script->SetNativeScript(NativeScript);
	return Script;
}

FString ULorelineScript::PrintScript() const
{
	if (!NativeScript) return FString();
	Loreline_String Result = Loreline_printScript(NativeScript);
	return Result.isNull() ? FString() : UTF8_TO_TCHAR(Result.c_str());
}
