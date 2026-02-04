var Module = {};
Module.print = Module.printErr = function(s) {
    postMessage({id:"output", data:s})
}

importScripts("objdump.js");

Module.onRuntimeInitialized = function() {
    postMessage({id:"ready"});
};

onmessage = function(e) {
    if (e.data.id === "disassemble") {
        var input = e.data.input;
        try {
            Module.FS_unlink("/input");
        } catch(e) {}
        Module.FS_createDataFile("/", "input", input, true, true);
        Module.arguments.push(...e.data.cmd.split(" "));
        Module.arguments.push("input", "-D");
        Module.callMain(Module.arguments);
    }
};
