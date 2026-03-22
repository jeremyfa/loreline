#pragma once

#include "CoreMinimal.h"
#include "UObject/NoExportTypes.h"
#include "LorelineTypes.h"
#include "LorelineInterpreter.generated.h"

struct Loreline_Interpreter;
struct Loreline_TextTag;
struct Loreline_ChoiceOption;
struct Loreline_Value;
class Loreline_String;

DECLARE_DYNAMIC_MULTICAST_DELEGATE_ThreeParams(FOnLorelineDialogue,
	const FString&, Character,
	const FString&, Text,
	const TArray<FLorelineTextTag>&, Tags);

DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FOnLorelineChoice,
	const TArray<FLorelineChoiceOption>&, Options);

DECLARE_DYNAMIC_MULTICAST_DELEGATE(FOnLorelineFinished);

UCLASS(BlueprintType)
class LORELINE_API ULorelineInterpreter : public UObject
{
	GENERATED_BODY()

public:
	virtual void BeginDestroy() override;

	/** Advance to the next line of dialogue. */
	UFUNCTION(BlueprintCallable, Category = "Loreline|Playback")
	void Advance();

	/** Select a choice option by index. */
	UFUNCTION(BlueprintCallable, Category = "Loreline|Playback")
	void Select(int32 Index);

	/** Start execution from a named beat. */
	UFUNCTION(BlueprintCallable, Category = "Loreline|Playback")
	void Start(const FString& BeatName);

	/** Save interpreter state to a string. */
	UFUNCTION(BlueprintCallable, Category = "Loreline|Playback")
	FString SaveState() const;

	/** Restore interpreter state from a previously saved string. */
	UFUNCTION(BlueprintCallable, Category = "Loreline|Playback")
	void RestoreState(const FString& SaveData);

	/** Get a character's field value. */
	UFUNCTION(BlueprintCallable, Category = "Loreline|State")
	FLorelineValue GetCharacterField(const FString& Character, const FString& Field) const;

	/** Set a character's field value. */
	UFUNCTION(BlueprintCallable, Category = "Loreline|State")
	void SetCharacterField(const FString& Character, const FString& Field, const FLorelineValue& Value);

	/** Get a state field value (scope-aware). */
	UFUNCTION(BlueprintCallable, Category = "Loreline|State")
	FLorelineValue GetStateField(const FString& Field) const;

	/** Set a state field value (scope-aware). */
	UFUNCTION(BlueprintCallable, Category = "Loreline|State")
	void SetStateField(const FString& Field, const FLorelineValue& Value);

	/** Get a top-level state field value (global scope). */
	UFUNCTION(BlueprintCallable, Category = "Loreline|State")
	FLorelineValue GetTopLevelStateField(const FString& Field) const;

	/** Set a top-level state field value (global scope). */
	UFUNCTION(BlueprintCallable, Category = "Loreline|State")
	void SetTopLevelStateField(const FString& Field, const FLorelineValue& Value);

	/** Get info about the currently executing node. */
	UFUNCTION(BlueprintCallable, Category = "Loreline|State")
	FLorelineNodeInfo CurrentNode() const;

	/** Fired when dialogue is encountered. */
	UPROPERTY(BlueprintAssignable, Category = "Loreline|Events")
	FOnLorelineDialogue OnDialogue;

	/** Fired when a choice is presented. */
	UPROPERTY(BlueprintAssignable, Category = "Loreline|Events")
	FOnLorelineChoice OnChoice;

	/** Fired when the script finishes. */
	UPROPERTY(BlueprintAssignable, Category = "Loreline|Events")
	FOnLorelineFinished OnFinished;

	void SetNativeInterpreter(Loreline_Interpreter* InInterp) { NativeInterpreter = InInterp; }

	// Native callback bridge (static so they can be passed as C function pointers)
	static void OnDialogueCallback(Loreline_Interpreter* Interp, Loreline_String Character,
		Loreline_String Text, const Loreline_TextTag* Tags, int TagCount,
		void (*AdvanceFn)(void), void* UserData);
	static void OnChoiceCallback(Loreline_Interpreter* Interp,
		const Loreline_ChoiceOption* Options, int OptionCount,
		void (*SelectFn)(int), void* UserData);
	static void OnFinishCallback(Loreline_Interpreter* Interp, void* UserData);

private:
	Loreline_Interpreter* NativeInterpreter = nullptr;
	void (*PendingAdvance)(void) = nullptr;
	void (*PendingSelect)(int) = nullptr;

	static TArray<FLorelineTextTag> ConvertTags(const Loreline_TextTag* Tags, int TagCount);
	static TArray<FLorelineChoiceOption> ConvertOptions(const Loreline_ChoiceOption* Options, int OptionCount);
	static FLorelineValue NativeToValue(const Loreline_Value& Value);
	static Loreline_Value ValueToNative(const FLorelineValue& Value);
};
