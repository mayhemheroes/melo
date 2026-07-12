#![no_main]
use libfuzzer_sys::fuzz_target;
use melo::MidiGenerationOptions;

fuzz_target!(|data: &str| {
    let options = MidiGenerationOptions { ticks_per_beat: 16 };
    let _ = melo::compile_to_midi(data, Some("file"), &options);
});
