<?php

/**
 * Loreline bootstrap: loads the generated Haxe runtime (php/lib) and
 * registers an autoloader for the public Loreline\ wrapper classes.
 *
 * The generated runtime lives under the Loreline\Internal namespace and
 * ships its own autoloader, registered by lib/index.php.
 */

require_once __DIR__ . '/../lib/index.php';

spl_autoload_register(function (string $class): void {
    if (strncmp($class, 'Loreline\\', 9) !== 0) {
        return;
    }
    if (strncmp($class, 'Loreline\\Internal\\', 18) === 0) {
        return;
    }
    $file = __DIR__ . '/' . str_replace('\\', '/', substr($class, 9)) . '.php';
    if (is_file($file)) {
        require_once $file;
    }
});
