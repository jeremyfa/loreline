<?php

namespace Loreline;

use Loreline\Internal\loreline\Arrays as HxArrays;
use Loreline\Internal\loreline\Objects as HxObjects;

/**
 * Recursive conversion between the runtime's internal Haxe containers and
 * native PHP arrays.
 *
 * PHP arrays are value types (copy on write), so values crossing the boundary
 * are snapshots: reading state produces an independent PHP array, and writing
 * state deep-copies the given PHP array back into runtime containers.
 */
final class Marshal
{
    /**
     * Convert a runtime value to its native PHP equivalent.
     *
     * Haxe arrays become PHP lists, runtime fields objects become PHP
     * associative arrays, scalars pass through unchanged. Values that are
     * neither (opaque runtime handles) are returned as is.
     */
    public static function hxToPhp(mixed $value, mixed $rawInterpreter = null): mixed
    {
        if ($value === null || is_scalar($value)) {
            return $value;
        }
        if (HxArrays::isArray($value)) {
            $result = [];
            $length = HxArrays::arrayLength($value);
            for ($i = 0; $i < $length; $i++) {
                $result[] = self::hxToPhp(HxArrays::arrayGet($value, $i), $rawInterpreter);
            }
            return $result;
        }
        if (HxObjects::isFields($value)) {
            $result = [];
            $keys = HxObjects::getFields($rawInterpreter, $value);
            $length = HxArrays::arrayLength($keys);
            for ($i = 0; $i < $length; $i++) {
                $key = (string) HxArrays::arrayGet($keys, $i);
                $result[$key] = self::hxToPhp(
                    HxObjects::getField($rawInterpreter, $value, $key),
                    $rawInterpreter
                );
            }
            return $result;
        }
        return $value;
    }

    /**
     * Convert a native PHP value to its runtime equivalent.
     *
     * PHP lists become Haxe arrays, associative arrays become runtime fields
     * objects, scalars pass through unchanged. An empty PHP array is treated
     * as an empty list. Numeric keys are converted back to string field names.
     */
    public static function phpToHx(mixed $value, mixed $rawInterpreter = null): mixed
    {
        if (is_array($value)) {
            if (array_is_list($value)) {
                $result = HxArrays::createArray();
                foreach ($value as $item) {
                    HxArrays::arrayPush($result, self::phpToHx($item, $rawInterpreter));
                }
                return $result;
            }
            $result = HxObjects::createFields($rawInterpreter);
            foreach ($value as $key => $item) {
                HxObjects::setField(
                    $rawInterpreter,
                    $result,
                    (string) $key,
                    self::phpToHx($item, $rawInterpreter)
                );
            }
            return $result;
        }
        if ($value instanceof Node) {
            return $value->internal();
        }
        if ($value instanceof Interpreter) {
            return $value->internal();
        }
        return $value;
    }
}
