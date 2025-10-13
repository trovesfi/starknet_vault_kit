#!/usr/bin/env node

import { Command } from 'commander';
import { execSync } from 'child_process';
import { readFileSync, existsSync } from 'fs';
import { join, resolve } from 'path';
import { ContractClass, extractContractHashes, json } from 'starknet';

const program = new Command();

interface CompileOptions {
  package: string;
  contract: string;
  profile?: string;
}

/**
 * Compile a Cairo contract using Scarb and return its class hash
 */
async function compileContract(options: CompileOptions): Promise<string> {
  const { package: packageName, contract: contractName, profile = 'release' } = options;
  
  console.log(`🔨 Compiling contract ${contractName} from package ${packageName}...`);
  
  // Determine the package path - look for packages directory in current or parent directories
  let projectRoot = resolve(process.cwd(), '..');
  while (!existsSync(join(projectRoot, 'packages')) && projectRoot !== '/') {
    projectRoot = resolve(projectRoot, '..');
  }
  
  if (!existsSync(join(projectRoot, 'packages'))) {
    throw new Error('Could not find packages directory. Please run from project root or a subdirectory.');
  }
  
  // Check if Scarb.toml exists in the package
  const scarbTomlPath = join(projectRoot, 'Scarb.toml');
  if (!existsSync(scarbTomlPath)) {
    throw new Error(`Scarb.toml not found in package ${packageName}`);
  }
  
  try {
    // Compile the contract using Scarb
    console.log(`📦 Building package ${packageName} with profile ${profile}...`);
    const buildCommand = `scarb --profile ${profile} build --package ${packageName}`;
    execSync(buildCommand, { 
      stdio: 'pipe',
      cwd: projectRoot
    });
    
    console.log('✅ Contract compiled successfully');
    
    // Find the compiled contract file
    const targetDir = join(projectRoot, 'target', profile);
    
    const compiledSierra = json.parse(
        readFileSync(`${targetDir}/${packageName}_${contractName}.contract_class.json`).toString("ascii")
    )
    const compiledCasm = json.parse(
    readFileSync(`${targetDir}/${packageName}_${contractName}.compiled_contract_class.json`).toString("ascii")
    )
    
    // Read and parse the contract class
    const payload = {
        contract: compiledSierra,
        casm: compiledCasm
    };
    
    const result = extractContractHashes(payload);

    console.log(`🎯 Class hash: ${result.classHash}`);
    return result.classHash;
    
  } catch (error) {
    if (error instanceof Error) {
      throw new Error(`Compilation failed: ${error.message}`);
    }
    throw error;
  }
}

/**
 * List available packages and contracts
 */
function listPackages(): void {
  console.log('📦 Available packages:');
  
  // Find project root
  let projectRoot = process.cwd();
  while (!existsSync(join(projectRoot, 'packages')) && projectRoot !== '/') {
    projectRoot = resolve(projectRoot, '..');
  }
  
  if (!existsSync(join(projectRoot, 'packages'))) {
    console.log('  No packages directory found');
    return;
  }
  
  const packagesDir = join(projectRoot, 'packages');
  
  if (!existsSync(packagesDir)) {
    console.log('  No packages directory found');
    return;
  }
  
  try {
    const packages = execSync('ls packages', { encoding: 'utf8', cwd: projectRoot }).trim().split('\n');
    
    packages.forEach(pkg => {
      const packagePath = join(packagesDir, pkg);
      const scarbTomlPath = join(packagePath, 'Scarb.toml');
      
      if (existsSync(scarbTomlPath)) {
        console.log(`  📁 ${pkg}`);
        
        // Try to find contract files
        const srcPath = join(packagePath, 'src');
        if (existsSync(srcPath)) {
          try {
            const contractFiles = execSync(`find ${srcPath} -name "*.cairo" -type f`, { encoding: 'utf8' })
              .trim()
              .split('\n')
              .filter(file => file.includes('contract') || file.includes('interface'));
            
            if (contractFiles.length > 0) {
              contractFiles.forEach(file => {
                const fileName = file.split('/').pop()?.replace('.cairo', '') || '';
                console.log(`    📄 ${fileName}`);
              });
            }
          } catch {
            // Ignore errors when searching for contract files
          }
        }
      }
    });
  } catch (error) {
    console.log('  Error listing packages');
  }
}

// CLI setup
program
  .name('starknet-compiler')
  .description('Compile Cairo contracts and get their class hashes')
  .version('1.0.0');

program
  .command('compile')
  .description('Compile a contract and return its class hash')
  .requiredOption('-p, --package <package>', 'Package name (e.g., vault, vault_allocator)')
  .requiredOption('-c, --contract <contract>', 'Contract name')
  .option('--profile <profile>', 'Build profile (dev, release)', 'release')
  .action(async (options) => {
    try {
      const classHash = await compileContract(options);
      console.log(`\n🎉 Success! Class hash: ${classHash}`);
    } catch (error) {
      console.error(`❌ Error: ${error instanceof Error ? error.message : 'Unknown error'}`);
      process.exit(1);
    }
  });

program
  .command('list')
  .description('List available packages and contracts')
  .action(() => {
    listPackages();
  });

program.parse();

// Show help if no command provided
if (!process.argv.slice(2).length) {
  program.outputHelp();
}
