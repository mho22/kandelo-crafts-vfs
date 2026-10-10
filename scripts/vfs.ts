import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';


const __dirname = path.dirname( fileURLToPath( import.meta.url ) );

const root = path.resolve( __dirname, '..' );

const binaries = path.resolve( root, 'binaries' );

const config = path.resolve( root, 'config/demo.json' );

const session = path.resolve( root, 'config/session.json' );

const output = path.resolve( root, 'vfs/photocraft.vfs' );

const SIZE = 128 * 1024 * 1024;

const DIRECTORIES = [ '/etc', '/etc/kandelo', '/usr', '/usr/local', '/usr/local/bin', '/usr/share', '/usr/share/X11', '/usr/share/X11/xkb' ];

const PROGRAMS = [ 'wlcompositor', 'photocraft', 'dash' ];

const ABI = /ABI_VERSION = (\d+)/;


const kandelo = () =>
{
	const candidates = [ process.env.KANDELO, path.resolve( root, '../kandelo' ), path.resolve( root, '../../kandelo' ) ];

	for( const candidate of candidates ) if( candidate && fs.existsSync( path.join( candidate, 'host/dist/index.js' ) ) ) return candidate;

	throw new Error( 'kandelo checkout not found, or its host bundle is not built. Run `npm run build` in the checkout\'s host directory, or set KANDELO to its path.' );
};

const main = async () =>
{
	const checkout = kandelo();

	const { MemoryFileSystem } = await import( path.join( checkout, 'host/dist/index.js' ) );

	const abi = ABI.exec( fs.readFileSync( path.join( checkout, 'host/src/generated/abi.ts' ), 'utf8' ) );

	if( !abi ) throw new Error( 'ABI_VERSION not found in host/src/generated/abi.ts' );

	const abiVersion = Number( abi[ 1 ] );

	const image = MemoryFileSystem.create( new SharedArrayBuffer( SIZE ) );

	const write = ( vfsPath : string, bytes : Uint8Array, mode : number ) =>
	{
		const fd = image.open( vfsPath, 0x241, mode );

		image.write( fd, bytes, null, bytes.length );

		image.close( fd );

		console.log( `${vfsPath} (${bytes.length} bytes)` );
	};

	for( const directory of DIRECTORIES ) image.mkdir( directory, 0o755 );

	image.mkdir( '/tmp', 0o1777 );

	write( '/etc/kandelo/demo.json', fs.readFileSync( config ), 0o644 );

	write( '/etc/kandelo/experimental-terminal-session.json', fs.readFileSync( session ), 0o644 );

	for( const name of PROGRAMS ) write( `/usr/local/bin/${name}`, fs.readFileSync( path.join( binaries, `${name}.wasm` ) ), 0o755 );

	const bytes = await image.saveImage( {
		metadata : { version : 1, kernelAbi : abiVersion, createdBy : 'scripts/vfs.ts' },
		trimFreeCapacity : true
	} );

	fs.mkdirSync( path.dirname( output ), { recursive : true } );

	fs.writeFileSync( output, bytes );

	console.log( `${output} (${bytes.length} bytes)` );
};

main();
