import fs from 'fs';
import path from 'path';
import { fileURLToPath, pathToFileURL } from 'url';


const __dirname = path.dirname( fileURLToPath( import.meta.url ) );

const root = path.resolve( __dirname, '..' );

const binaries = path.resolve( root, 'binaries' );

const configs = path.resolve( root, 'config' );

const output = path.resolve( root, 'public/photocraft.vfs' );

const SIZE = 128 * 1024 * 1024;

const DIRECTORIES = [ '/etc', '/etc/kandelo', '/usr', '/usr/bin', '/usr/libexec', '/usr/libexec/kandelo', '/usr/local', '/usr/local/bin', '/usr/share', '/usr/share/X11', '/usr/share/X11/xkb', '/usr/share/kandelo', '/usr/share/kandelo/exchange-handlers.d' ];

const CONFIGS = { '/etc/passwd' : 'passwd', '/etc/kandelo/demo.json' : 'demo.json', '/etc/kandelo/experimental-terminal-session.json' : 'session.json', '/etc/kandelo/exchange.conf' : 'exchange.conf' };

const PROGRAMS = { '/usr/local/bin/wlcompositor' : 'wlcompositor', '/usr/local/bin/photocraft' : 'photocraft', '/usr/local/bin/dash' : 'dash', '/usr/bin/zenity' : 'zenity', '/usr/bin/xdg-open' : 'xdg-open', '/usr/libexec/kandelo/exchange-agent' : 'kxchgd', '/usr/libexec/kandelo/exchange-save' : 'exchange-save' };

const HANDLER = '/usr/share/kandelo/exchange-handlers.d/99-save.handler';

const EXCHANGE_GID = 120;

const ABI = /ABI_VERSION = (\d+)/;


const kandelo = () =>
{
	const candidates = [ process.env.KANDELO, path.resolve( root, 'kandelo' ) ];

	for( const candidate of candidates ) if( candidate && fs.existsSync( path.join( candidate, 'node_modules/tsx' ) ) ) return candidate;

	throw new Error( 'kandelo checkout not found, or its node modules are not installed. Run `git submodule update --init --recursive` and `npm ci` in kandelo, or set KANDELO to its path.' );
};

const main = async () =>
{
	const checkout = kandelo();

	const { tsImport } = await import( pathToFileURL( path.join( checkout, 'node_modules/tsx/dist/esm/api/index.mjs' ) ).href );

	const { KandeloImageFs } = await tsImport( path.join( checkout, 'images/vfs/lib/kandelo-image-fs.ts' ), import.meta.url );

	const abi = ABI.exec( fs.readFileSync( path.join( checkout, 'host/src/generated/abi.ts' ), 'utf8' ) );

	if( !abi ) throw new Error( 'ABI_VERSION not found in host/src/generated/abi.ts' );

	const abiVersion = Number( abi[ 1 ] );

	const image = KandeloImageFs.create();

	image.setImageCapacity( SIZE );

	const write = ( vfsPath : string, bytes : Uint8Array, mode : number ) =>
	{
		image.writeFile( vfsPath, bytes, mode );

		console.log( `${vfsPath} (${bytes.length} bytes)` );
	};

	for( const directory of DIRECTORIES ) image.mkdir( directory, 0o755 );

	image.mkdirWithOwner( '/etc/kandelo/exchange-handlers.d', 0o755, 0, EXCHANGE_GID );

	image.mkdir( '/root', 0o700 );

	image.mkdir( '/tmp', 0o1777 );

	for( const [ vfsPath, name ] of Object.entries( CONFIGS ) ) write( vfsPath, fs.readFileSync( path.join( configs, name ) ), 0o644 );

	write( HANDLER, fs.readFileSync( path.join( checkout, 'images/rootfs', HANDLER ) ), 0o644 );

	for( const [ vfsPath, name ] of Object.entries( PROGRAMS ) ) write( vfsPath, fs.readFileSync( path.join( binaries, `${name}.wasm` ) ), 0o755 );

	const bytes = await image.saveImage( {
		metadata : { version : 1, kernelAbi : abiVersion, createdBy : 'scripts/vfs.ts' }
	} );

	fs.mkdirSync( path.dirname( output ), { recursive : true } );

	fs.writeFileSync( output, bytes );

	console.log( `${output} (${bytes.length} bytes)` );
};

main();
