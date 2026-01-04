//! C6P Test Vector Generator
//!
//! Generates deterministic test vectors for all C6P modules.
//! All vectors use fixed seeds for reproducibility across implementations.

use anyhow::{Context, Result};
use clap::Parser;
use std::path::PathBuf;

mod crypto;
mod handshake;
mod identity;
mod sessions;

/// C6P Test Vector Generator - Generate deterministic test vectors for cross-implementation validation
#[derive(Parser, Debug)]
#[command(name = "c6p-gen-vectors")]
#[command(version = "1.0")]
#[command(about = "Generate C6P v1 test vectors", long_about = None)]
struct Args {
    /// Output directory (default: docs/)
    #[arg(short, long, default_value = "docs")]
    output: PathBuf,

    /// Generate only specific module (crypto, handshake, identity, sessions)
    #[arg(short, long)]
    module: Option<String>,

    /// Verbose output
    #[arg(short, long)]
    verbose: bool,

    /// Force overwrite existing files
    #[arg(short, long)]
    force: bool,
}

fn main() -> Result<()> {
    let args = Args::parse();

    println!("🔐 C6P Test Vector Generator v1.0");
    println!("📁 Output directory: {}", args.output.display());
    println!();

    // Ensure output directory exists
    if !args.output.exists() {
        anyhow::bail!(
            "Output directory does not exist: {}",
            args.output.display()
        );
    }

    // Generate vectors based on module selection
    match args.module.as_deref() {
        None => {
            // Generate all modules
            println!("🔄 Generating all test vectors...");
            generate_crypto_vectors(&args)?;
            generate_handshake_vectors(&args)?;
            generate_identity_vectors(&args)?;
            generate_sessions_vectors(&args)?;
        }
        Some("crypto") => generate_crypto_vectors(&args)?,
        Some("handshake") => generate_handshake_vectors(&args)?,
        Some("identity") => generate_identity_vectors(&args)?,
        Some("sessions") => generate_sessions_vectors(&args)?,
        Some(module) => {
            anyhow::bail!("Unknown module: {}. Valid modules: crypto, handshake, identity, sessions", module);
        }
    }

    println!();
    println!("✅ Test vector generation complete!");
    Ok(())
}

fn generate_crypto_vectors(args: &Args) -> Result<()> {
    println!("📦 Generating crypto test vectors...");
    let output_dir = args.output.join("crypto/test-vectors/v1");
    crypto::generate_all(&output_dir, args.verbose, args.force)
        .context("Failed to generate crypto vectors")?;
    println!("   ✓ Crypto vectors written to {}", output_dir.display());
    Ok(())
}

fn generate_handshake_vectors(args: &Args) -> Result<()> {
    println!("📦 Generating handshake test vectors...");
    let output_dir = args.output.join("handshake/test-vectors/v1");
    handshake::generate_all(&output_dir, args.verbose, args.force)
        .context("Failed to generate handshake vectors")?;
    println!("   ✓ Handshake vectors written to {}", output_dir.display());
    Ok(())
}

fn generate_identity_vectors(args: &Args) -> Result<()> {
    println!("📦 Generating identity test vectors...");
    let output_dir = args.output.join("identity/test-vectors/v1");
    identity::generate_all(&output_dir, args.verbose, args.force)
        .context("Failed to generate identity vectors")?;
    println!("   ✓ Identity vectors written to {}", output_dir.display());
    Ok(())
}

fn generate_sessions_vectors(args: &Args) -> Result<()> {
    println!("📦 Generating sessions test vectors...");
    let output_dir = args.output.join("Sessions/test-vectors/v1");
    sessions::generate_all(&output_dir, args.verbose, args.force)
        .context("Failed to generate sessions vectors")?;
    println!("   ✓ Sessions vectors written to {}", output_dir.display());
    Ok(())
}
