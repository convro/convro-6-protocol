# UniFFI Debug Notes

## Problem

UDL file (`c6p_ios.udl`) ma błędy składni które powodują panic w `build.rs`:

```
Error: parse error (from uniffi_build::generate_scaffolding)
```

## Strategia naprawy

1. Stworzyć minimalną UDL która się kompiluje
2. Dodawać funkcjonalność stopniowo
3. Testować po każdej zmianie
4. Dokumentować co działa

## UniFFI 0.28 Syntax Reference

### Basic Types (VERIFIED)
- `string` ✅
- `u8`, `u16`, `u32`, `u64` ✅
- `i8`, `i16`, `i32`, `i64` ✅
- `f32`, `f64` ✅
- `boolean` ✅
- `bytes` ❓ (może być `sequence<u8>` zamiast)

### Custom Types
- `dictionary Name { ... }` ✅
- `enum Name { ... }` ✅
- `interface Name { ... }` ✅

### Error Handling
- `[Error]` attribute ✅
- `[Throws=ErrorType]` ✅

### Optional Types
- `Type?` ✅ (nullable)

### Functions
- Top-level functions in namespace ✅
- Methods in interface ✅
- Constructor in interface ✅
- Static methods: `[Name=...]` attribute

## Suspected Issues

1. **`bytes` type** - UniFFI 0.28 może wymagać `sequence<u8>` zamiast `bytes`
2. **Optional custom types** - `OneTimePrekey?` może wymagać innej składni
3. **Static methods** - `static SessionState import_state(...)` może być niepoprawne
4. **Constructor syntax** - `constructor(...)` może wymagać atrybutu

## Next Steps

1. Sprawdzić przykłady UniFFI 0.28
2. Przetestować minimalną UDL
3. Stopniowo dodawać typy i funkcje
