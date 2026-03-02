import java.io.*;
import java.util.*;
import java.util.jar.*;
import java.util.zip.*;
import org.objectweb.asm.*;
import org.objectweb.asm.commons.*;

/**
 * ASM-based package relocator for Loreline JVM target.
 *
 * Relocates packages in the Haxe-generated jar:
 *   loreline/* -> loreline/runtime/*
 *   haxe/*     -> loreline/internal/*
 *   hscript/*  -> loreline/internal/hscript/*
 *
 * Also fixes Haxe JVM backend generic erasure issues:
 *   The Haxe JVM backend generates checkcast instructions that cast Object[]
 *   to typed arrays (e.g. [Lloreline/RuntimeState;) when iterating generic
 *   containers like Int64Map<V>. These fail at runtime because the backing
 *   stores are always Object[]. This relocator transforms the bytecode to
 *   move the cast from the array level to the element level.
 *
 * This frees up the loreline/ package for the hand-written public Java API.
 */
public class Relocator {

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("Usage: java Relocator <input.jar> <output.jar>");
            System.exit(1);
        }

        String inputPath = args[0];
        String outputPath = args[1];

        Remapper remapper = new Remapper() {
            @Override
            public String map(String internalName) {
                if (internalName.startsWith("hscript/")) {
                    return "loreline/internal/hscript/" + internalName.substring("hscript/".length());
                }
                if (internalName.startsWith("haxe/")) {
                    return "loreline/internal/" + internalName.substring("haxe/".length());
                }
                if (internalName.startsWith("loreline/")) {
                    return "loreline/runtime/" + internalName.substring("loreline/".length());
                }
                return internalName;
            }
        };

        // Pass 1: Read all classes and build hierarchy map (with relocated names)
        Map<String, String> classHierarchy = new HashMap<>();
        Map<String, byte[]> classEntries = new LinkedHashMap<>();
        Map<String, byte[]> resourceEntries = new LinkedHashMap<>();
        Manifest manifest = null;

        try (JarInputStream jis = new JarInputStream(new FileInputStream(inputPath))) {
            manifest = jis.getManifest();
            JarEntry entry;
            while ((entry = jis.getNextJarEntry()) != null) {
                String name = entry.getName();
                byte[] bytes = readAllBytes(jis);
                if (name.endsWith(".class")) {
                    ClassReader cr = new ClassReader(bytes);
                    String relocated = remapper.map(cr.getClassName());
                    String superRelocated = cr.getSuperName() != null
                        ? remapper.map(cr.getSuperName()) : "java/lang/Object";
                    classHierarchy.put(relocated, superRelocated);
                    classEntries.put(name, bytes);
                } else if (!name.equals(JarFile.MANIFEST_NAME)) {
                    resourceEntries.put(name, bytes);
                }
            }
        }

        // Pass 2: Relocate, fix checkcasts, recompute frames
        try (JarOutputStream jos = new JarOutputStream(new FileOutputStream(outputPath))) {
            if (manifest != null) {
                JarEntry manifestEntry = new JarEntry(JarFile.MANIFEST_NAME);
                jos.putNextEntry(manifestEntry);
                manifest.write(jos);
                jos.closeEntry();
            }

            Set<String> writtenEntries = new HashSet<>();

            for (Map.Entry<String, byte[]> e : classEntries.entrySet()) {
                ClassReader cr = new ClassReader(e.getValue());
                ClassWriter cw = new HierarchyAwareClassWriter(
                    ClassWriter.COMPUTE_FRAMES, classHierarchy);
                ClassVisitor fixVisitor = new CheckcastFixVisitor(cw);
                ClassVisitor cv = new ClassRemapper(fixVisitor, remapper);
                cr.accept(cv, ClassReader.SKIP_FRAMES);
                byte[] relocated = cw.toByteArray();

                String newName = remapEntryName(e.getKey(), remapper);
                if (writtenEntries.add(newName)) {
                    jos.putNextEntry(new JarEntry(newName));
                    jos.write(relocated);
                    jos.closeEntry();
                }
            }

            for (Map.Entry<String, byte[]> e : resourceEntries.entrySet()) {
                String newName = remapResourceName(e.getKey());
                if (writtenEntries.add(newName)) {
                    jos.putNextEntry(new JarEntry(newName));
                    jos.write(e.getValue());
                    jos.closeEntry();
                }
            }
        }

        System.out.println("Relocated: " + inputPath + " -> " + outputPath);
    }

    private static String remapEntryName(String name, Remapper remapper) {
        String internal = name.substring(0, name.length() - 6);
        String remapped = remapper.map(internal);
        return remapped + ".class";
    }

    private static String remapResourceName(String name) {
        if (name.startsWith("hscript/")) {
            return "loreline/internal/hscript/" + name.substring("hscript/".length());
        }
        if (name.startsWith("haxe/")) {
            return "loreline/internal/" + name.substring("haxe/".length());
        }
        if (name.startsWith("loreline/")) {
            return "loreline/runtime/" + name.substring("loreline/".length());
        }
        return name;
    }

    private static byte[] readAllBytes(InputStream is) throws IOException {
        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        byte[] buf = new byte[8192];
        int n;
        while ((n = is.read(buf)) != -1) {
            bos.write(buf, 0, n);
        }
        return bos.toByteArray();
    }

    /**
     * ClassWriter that resolves common superclass using a pre-built hierarchy
     * from the jar contents, avoiding Class.forName() which can't find
     * relocated classes.
     */
    static class HierarchyAwareClassWriter extends ClassWriter {
        private final Map<String, String> hierarchy;

        HierarchyAwareClassWriter(int flags, Map<String, String> hierarchy) {
            super(flags);
            this.hierarchy = hierarchy;
        }

        @Override
        protected String getCommonSuperClass(String type1, String type2) {
            if (type1.equals("java/lang/Object") || type2.equals("java/lang/Object")) {
                return "java/lang/Object";
            }

            Set<String> ancestors1 = new HashSet<>();
            String t = type1;
            while (t != null && !t.equals("java/lang/Object")) {
                ancestors1.add(t);
                t = hierarchy.get(t);
            }
            ancestors1.add("java/lang/Object");

            t = type2;
            while (t != null) {
                if (ancestors1.contains(t)) return t;
                t = hierarchy.get(t);
            }
            return "java/lang/Object";
        }
    }

    /**
     * Fixes Haxe JVM backend generic erasure issue.
     *
     * Transforms bytecode patterns like:
     *   getfield _values:[Ljava/lang/Object;
     *   checkcast [Lloreline/runtime/RuntimeState;   // array-level cast (FAILS)
     *   iload N
     *   aaload                                        // produces RuntimeState
     *
     * Into:
     *   getfield _values:[Ljava/lang/Object;
     *   iload N
     *   aaload                                        // produces Object
     *   checkcast loreline/runtime/RuntimeState       // element-level cast (WORKS)
     *
     * For arraylength access, the checkcast is simply removed (arraylength
     * works on any array type).
     */
    static class CheckcastFixVisitor extends ClassVisitor {
        CheckcastFixVisitor(ClassVisitor cv) {
            super(Opcodes.ASM9, cv);
        }

        @Override
        public MethodVisitor visitMethod(int access, String name, String descriptor,
                                          String signature, String[] exceptions) {
            MethodVisitor mv = super.visitMethod(access, name, descriptor, signature, exceptions);
            return new CheckcastFixMethodVisitor(mv);
        }

        private static boolean isAppArrayType(String type) {
            return type.startsWith("[L") && (
                type.startsWith("[Lloreline/") ||
                type.startsWith("[Lhaxe/") ||
                type.startsWith("[Lhscript/")
            );
        }
    }

    /**
     * Method visitor that tracks pending array checkcast removals and inserts
     * element-level casts after aaload instructions.
     */
    static class CheckcastFixMethodVisitor extends MethodVisitor {
        // When non-null, an array checkcast was removed and this holds the element type
        private String pendingElementType = null;

        CheckcastFixMethodVisitor(MethodVisitor mv) {
            super(Opcodes.ASM9, mv);
        }

        @Override
        public void visitTypeInsn(int opcode, String type) {
            if (opcode == Opcodes.CHECKCAST && CheckcastFixVisitor.isAppArrayType(type)) {
                // Extract element type: "[Lloreline/runtime/RuntimeState;" -> "loreline/runtime/RuntimeState"
                pendingElementType = type.substring(2, type.length() - 1);
                // Skip the array-level checkcast
                return;
            }
            // Any other type instruction clears pending state
            pendingElementType = null;
            super.visitTypeInsn(opcode, type);
        }

        @Override
        public void visitInsn(int opcode) {
            if (opcode == Opcodes.AALOAD && pendingElementType != null) {
                // Emit the aaload first
                super.visitInsn(opcode);
                // Then insert element-level checkcast
                super.visitTypeInsn(Opcodes.CHECKCAST, pendingElementType);
                pendingElementType = null;
                return;
            }
            if (opcode == Opcodes.ARRAYLENGTH) {
                // arraylength works on Object[], no cast needed
                pendingElementType = null;
            }
            super.visitInsn(opcode);
        }

        // Keep pendingElementType alive through index-loading instructions
        // (iload, iload_N, etc. that appear between checkcast and aaload)
        @Override
        public void visitVarInsn(int opcode, int varIndex) {
            // iload/aload between checkcast removal and aaload: keep state
            super.visitVarInsn(opcode, varIndex);
        }

        @Override
        public void visitIincInsn(int varIndex, int increment) {
            super.visitIincInsn(varIndex, increment);
        }

        // Clear pending state on control flow changes
        @Override
        public void visitJumpInsn(int opcode, Label label) {
            pendingElementType = null;
            super.visitJumpInsn(opcode, label);
        }

        @Override
        public void visitLabel(Label label) {
            pendingElementType = null;
            super.visitLabel(label);
        }

        @Override
        public void visitMethodInsn(int opcode, String owner, String name,
                                     String descriptor, boolean isInterface) {
            pendingElementType = null;
            super.visitMethodInsn(opcode, owner, name, descriptor, isInterface);
        }

        @Override
        public void visitFieldInsn(int opcode, String owner, String name, String descriptor) {
            // Don't clear pending on field access — the getfield -> checkcast -> iload -> aaload
            // pattern sometimes has a getfield for the index array between checkcast and aaload
            super.visitFieldInsn(opcode, owner, name, descriptor);
        }

        @Override
        public void visitIntInsn(int opcode, int operand) {
            // bipush, sipush etc. can appear as index computation — keep state
            super.visitIntInsn(opcode, operand);
        }

        @Override
        public void visitLdcInsn(Object value) {
            pendingElementType = null;
            super.visitLdcInsn(value);
        }
    }
}
