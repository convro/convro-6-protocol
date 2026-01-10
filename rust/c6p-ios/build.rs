fn main() {
    // Generate UniFFI scaffolding from UDL
    uniffi::generate_scaffolding("src/c6p_ios.udl").unwrap();
}
