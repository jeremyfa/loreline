using UnityEditor.AssetImporters;
using UnityEngine;

[ScriptedImporter(1, "lor")]
public class LorelineImporter : ScriptedImporter
{
    public override void OnImportAsset(AssetImportContext ctx)
    {
        TextAsset textAsset = new TextAsset(System.IO.File.ReadAllText(ctx.assetPath));
        ctx.AddObjectToAsset("text", textAsset);
        ctx.SetMainObject(textAsset);
    }
}
