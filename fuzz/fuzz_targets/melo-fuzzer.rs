#![no_main]
use libfuzzer_sys::fuzz_target;
use melo::MidiGenerationOptions;
use melo::compile_to_midi;

fn create_filename(instr: &str) -> Option<&str> {
    Some(instr)
}

fuzz_target!(|data: &str| {
    // fuzzed code goes here
    let options = MidiGenerationOptions { ticks_per_beat: 16 };
    let filename = "file";
    let result = melo::compile_to_midi(&data, create_filename(filename), &options);
});