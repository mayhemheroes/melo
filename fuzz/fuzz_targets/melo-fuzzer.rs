#![no_main]
use libfuzzer_sys::fuzz_target;
use melo::MidiGenerationOptions;
use melo::compile_to_midi;

fn create_filename(instr: &str) -> Option<&str> {
    Some(instr)
}

fuzz_target!(|data: &[u8]| {
    // fuzzed code goes here
    let in_string = std::str::from_utf8(&data);
    match in_string {
        Ok(input) => {
            let options = MidiGenerationOptions { ticks_per_beat: 16 };
            let filename = "file";
            let result = melo::compile_to_midi(&input, create_filename(filename), &options);
        }
        Err(_) => ()
    }
});