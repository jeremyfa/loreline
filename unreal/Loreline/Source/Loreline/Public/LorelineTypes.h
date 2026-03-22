#pragma once

#include "CoreMinimal.h"
#include "LorelineTypes.generated.h"

UENUM(BlueprintType)
enum class ELorelineValueType : uint8
{
	Null        UMETA(DisplayName = "Null"),
	Int         UMETA(DisplayName = "Int"),
	Float       UMETA(DisplayName = "Float"),
	Bool        UMETA(DisplayName = "Bool"),
	String      UMETA(DisplayName = "String")
};

USTRUCT(BlueprintType)
struct LORELINE_API FLorelineValue
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Loreline")
	ELorelineValueType Type = ELorelineValueType::Null;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Loreline")
	int32 IntValue = 0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Loreline")
	double FloatValue = 0.0;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Loreline")
	bool BoolValue = false;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Loreline")
	FString StringValue;

	static FLorelineValue MakeNull() { FLorelineValue V; return V; }
	static FLorelineValue MakeInt(int32 Val) { FLorelineValue V; V.Type = ELorelineValueType::Int; V.IntValue = Val; return V; }
	static FLorelineValue MakeFloat(double Val) { FLorelineValue V; V.Type = ELorelineValueType::Float; V.FloatValue = Val; return V; }
	static FLorelineValue MakeBool(bool Val) { FLorelineValue V; V.Type = ELorelineValueType::Bool; V.BoolValue = Val; return V; }
	static FLorelineValue MakeString(const FString& Val) { FLorelineValue V; V.Type = ELorelineValueType::String; V.StringValue = Val; return V; }
};

USTRUCT(BlueprintType)
struct LORELINE_API FLorelineTextTag
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Loreline")
	FString Value;

	UPROPERTY(BlueprintReadOnly, Category = "Loreline")
	int32 Offset = 0;

	UPROPERTY(BlueprintReadOnly, Category = "Loreline")
	bool bClosing = false;
};

USTRUCT(BlueprintType)
struct LORELINE_API FLorelineChoiceOption
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Loreline")
	FString Text;

	UPROPERTY(BlueprintReadOnly, Category = "Loreline")
	TArray<FLorelineTextTag> Tags;

	UPROPERTY(BlueprintReadOnly, Category = "Loreline")
	bool bEnabled = true;
};

USTRUCT(BlueprintType)
struct LORELINE_API FLorelineNodeInfo
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Loreline")
	FString Type;

	UPROPERTY(BlueprintReadOnly, Category = "Loreline")
	int32 Line = 0;

	UPROPERTY(BlueprintReadOnly, Category = "Loreline")
	int32 Column = 0;

	UPROPERTY(BlueprintReadOnly, Category = "Loreline")
	int32 Offset = 0;

	UPROPERTY(BlueprintReadOnly, Category = "Loreline")
	int32 Length = 0;
};
