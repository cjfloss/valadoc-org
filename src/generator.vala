/* generator.vala
 *
 * Copyright (C) 2012  Florian Brosch
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 *
 * Author:
 * 	Florian Brosch <flo.brosch@gmail.com>
 */


//
// This code is not supposed to be good. It's just a dirty script to reduce my work.
// Feel free to decrease the code quality even more.
//


using Gee;


public class Valadoc.IndexGenerator : Valadoc.ValadocOrgDoclet {
	private HashMap<string, Package> packages_per_name = new HashMap<string, Package> ();

	private void register_package (Package pkg) {
		packages_per_name.set (pkg.name, pkg);
	}

	[CCode (array_length = false, array_null_terminated = true)]
	private static string[] requested_packages;
	private static bool regenerate_all_packages;
	private static string output_directory;
	private static string metadata_path;
	private static string docletpath;
	private static string vapidir;
	private static string driver;
	private static bool download_images;
	private static string prefix;
	private static bool skip_existing;
	private static string girdir = "girs/gir-1.0";

	public IndexGenerator (ErrorReporter reporter) {
		this.reporter = new ErrorReporter ();
	}

	private const GLib.OptionEntry[] options = {
		{ "prefix", 0, 0, OptionArg.STRING, ref prefix, "package prefix (e.g. stable, unstable", null},
		{ "all", 0, 0, OptionArg.NONE, ref regenerate_all_packages, "Regenerate documentation for all packages", null },
		{ "directory", 'o', 0, OptionArg.FILENAME, ref output_directory, "Output directory", "DIRECTORY" },
		{ "driver", 'o', 0, OptionArg.FILENAME, ref driver, "Output directory", "DIRECTORY" },
		{ "download-images", 0, 0, OptionArg.NONE, ref download_images, "Downlaod images", null },
		{ "doclet", 0, 0, OptionArg.STRING, ref docletpath, "Name of an included doclet or path to custom doclet", "PLUGIN"},
		{ "vapidir", 0, 0, OptionArg.STRING, ref vapidir, "Look for package bindings in DIRECTORY", "DIRECTORY"},
		{ "skip-existing", 0, 0, OptionArg.NONE, ref skip_existing, "Skip existing packages", null },
		{ "", 0, 0, OptionArg.FILENAME_ARRAY, ref requested_packages, null, "FILE..." },
		{ null }
	};

	private void load_metadata (string filename) {
		MarkupReader reader = new MarkupReader (filename, reporter);

		MarkupSourceLocation begin;
		MarkupSourceLocation end;

		var current_token = reader.read_token (out begin, out end);
		current_token = reader.read_token (out begin, out end);
		current_token = reader.read_token (out begin, out end);

		if (current_token != MarkupTokenType.START_ELEMENT || reader.name != "packages") {
			reporter.simple_error ("error: Expected: <packages>");
			return ;
		}

		current_token = reader.read_token (out begin, out end);

		while (current_token != MarkupTokenType.END_ELEMENT && current_token != MarkupTokenType.EOF) {
			if (current_token != MarkupTokenType.START_ELEMENT || !(reader.name == "package" || reader.name == "external-package")) {
				reporter.simple_error ("error: Expected: <package> (got: %s '%s')", current_token.to_string (), reader.name);
				return ;
			}

			string start_tag = reader.name;

			string? ignore = reader.get_attribute ("ignore");
			if (ignore == null || ignore != "true") {
				string? maintainers = reader.get_attribute ("maintainers");
				string? name = reader.get_attribute ("name");
				string? c_docs = reader.get_attribute ("c-docs");
				string? home = reader.get_attribute ("home");
				string? deprecated_str = reader.get_attribute ("deprecated");
				bool is_deprecated = false;
				if (deprecated_str != null && deprecated_str == "true") {
					is_deprecated = true;
				}


				if (name == null) {
					reporter.simple_error ("error: %s: Missing attribute: name=\"\"", start_tag);
					return ;
				}

				if (start_tag == "external-package") {
					string? external_link = reader.get_attribute ("link");;
					string? devhelp_link = reader.get_attribute ("devhelp");
					if (external_link == null) {
						reporter.simple_error ("error: %s: Missing attribute: link=\"\" in %s", start_tag, name);
						return ;
					} else {
						register_package (new ExternalPackage (name, external_link, maintainers, devhelp_link, home, c_docs, is_deprecated));
					}
				} else {
					string? gir_name = reader.get_attribute ("gir");
					string? flags = reader.get_attribute ("flags");
					register_package (new Package (name, gir_name, maintainers, home, c_docs, flags, is_deprecated));
				}
			}

			current_token = reader.read_token (out begin, out end);

			if (current_token != MarkupTokenType.END_ELEMENT || reader.name != start_tag) {
				reporter.simple_error ("error: Expected: </package> (got: %s '%s')", current_token.to_string (), reader.name);				return ;
			}

			current_token = reader.read_token (out begin, out end);
		}

		if (current_token != MarkupTokenType.END_ELEMENT || reader.name != "packages") {
			reporter.simple_error ("error: Expected: </packages> (got: %s '%s')", current_token.to_string (), reader.name);
			return ;
		}
	}

	private class Package {
		public string? devhelp_link;
		public string? maintainers;
		public string online_link;
		public string? gir_name;
		public string name;
		public string? home;
		public string? c_docs;
		public string flags;
		public bool is_deprecated;

		public virtual string get_documentation_source () {
			StringBuilder builder = new StringBuilder ();

			if (get_gir_file () != null) {
				builder.append (".gir");
			}

			if (get_valadoc_file () != null) {
				builder.append ((builder.len == 0)? ".valadoc" : ", .valadoc");
			}

			return (builder.len == 0)? "none" : builder.str;
		}

		protected Package.dummy () {}

		public Package (string name, string? gir_name = null, string? maintainers = null, string? home = null, string? c_docs = null, string? flags = null, bool is_deprecated = false) {
			devhelp_link = "/" + name + "/" + name + ".tar.bz2";
			online_link = "/" + name + "/index.htm";
			this.is_deprecated = is_deprecated;
			this.maintainers = maintainers;
			this.gir_name = gir_name;
			this.c_docs = c_docs;
			this.name = name;
			this.home = home;
			this.flags = flags ?? "";
		}

		public string? get_gir_file_metadata_path () {
			string path = Path.build_path (Path.DIR_SEPARATOR_S, "documentation", name, gir_name + ".valadoc.metadata");
			if (FileUtils.test (path, FileTest.IS_REGULAR)) {
				return Path.get_dirname (path);
			}

			return null;
		}

		public virtual string? get_gir_file () {
			if (gir_name == null) {
				return null;
			}

			string path = Path.build_path (Path.DIR_SEPARATOR_S, "girs", "gir-1.0", gir_name + ".gir");
			if (FileUtils.test (path, FileTest.IS_REGULAR)) {
				return path;
			}

			return null;
		}

		public virtual string? get_catalog_file () {
			string path = Path.build_path (Path.DIR_SEPARATOR_S, "documentation", name, name + ".catalog");
			if (FileUtils.test (path, FileTest.IS_REGULAR)) {
				return path;
			}

			return null;
		}

		public virtual string? get_valadoc_file () {
			string path = Path.build_path (Path.DIR_SEPARATOR_S, "documentation", name, name + ".valadoc");
			if (FileUtils.test (path, FileTest.IS_REGULAR)) {
				return path;
			}

			return null;
		}

		public virtual string? get_vapi_path () {
			string path = Path.build_filename (vapidir, name + ".vapi");
			if (FileUtils.test (path, FileTest.IS_REGULAR)) {
				return path;
			}

			path = Path.build_path (Path.DIR_SEPARATOR_S, "girs", "vala", "vapi", name + ".vapi");
			if (FileUtils.test (path, FileTest.IS_REGULAR)) {
				return path;
			}			

			return null;
		}
	}

	private class ExternalPackage : Package {

		public ExternalPackage (string name, string online_link, string? maintainers, string? devhelp_link, string? home, string? c_docs, bool is_deprecated) {
			Package.dummy ();

			this.is_deprecated = is_deprecated;
			this.devhelp_link = devhelp_link;
			this.online_link = online_link;
			this.maintainers = maintainers;
			this.c_docs = c_docs;
			this.home = home;
			this.name = name;
		}

		public override string get_documentation_source () {
			return "unknown";
		}

		public override string? get_gir_file () {
			return null;
		}

		public override string? get_valadoc_file () {
			return null;
		}

		public override string? get_vapi_path () {
			return null;
		}

		public override string? get_catalog_file () {
			return null;
		}
	}

	public void load (string path) throws Error {
		Dir dirptr = Dir.open (path);
		string? dir;

		while ((dir = dirptr.read_name ()) != null) {
			string dir_path = Path.build_path (Path.DIR_SEPARATOR_S, path, dir);
			if (dir == ".sphinx") {
				continue ;
			}

			if (FileUtils.test (dir_path, FileTest.IS_DIR)) {
				if (!packages_per_name.has_key (dir)) {
					register_package (new Package (dir));
				}
			}
		}
	}

	private ArrayList<Package> get_sorted_package_list () {
		ArrayList<Package> packages = new ArrayList<Package> ();
		packages.add_all (packages_per_name.values);
		packages.sort ((a, b) => {
			return ((Package) a).name.ascii_casecmp (((Package) b).name);
		});

		return packages;
	}

	private void generate_navigation (string path) {
		GLib.FileStream file = GLib.FileStream.open (path, "w");
		var writer = new Html.MarkupWriter (file);

		writer.start_tag ("div", {"class", "site_navigation"});
		writer.start_tag ("ul", {"class", "navi_main"});

		ArrayList<Package> packages = get_sorted_package_list ();
		foreach (Package pkg in packages) {
			if (pkg is ExternalPackage) {
				writer.start_tag ("li", {"class", "package"}).start_tag ("a", {"href", pkg.online_link}).text (pkg.name).end_tag ("a").simple_tag ("img", {"src", "/external_link.png"}).end_tag ("li");
			} else {
				writer.start_tag ("li", {"class", "package"}).start_tag ("a", {"href", pkg.online_link}).text (pkg.name).end_tag ("a").end_tag ("li");
			}
		}

		writer.end_tag ("ul");
		writer.end_tag ("div");
	}

	private void generate_index (string path) {
		GLib.FileStream file = GLib.FileStream.open (path, "w");
		var writer = new Html.MarkupWriter (file);

		writer.start_tag ("div", {"class", "site_content"});

		writer.start_tag ("h1", {"class", "main_title"}).text ("Packages").end_tag ("h1");
		writer.simple_tag ("hr", {"class", "main_hr"});

		writer.start_tag ("h2").text ("Submitting API-Bugs and Patches").end_tag ("h2");
		writer.start_tag ("p").text ("For all bindings where the status is not marked as external, and unless otherwise noted, bugs and patches should be submitted to the bindings component in the Vala product in the GNOME Bugzilla.").end_tag ("p");

		writer.start_tag ("h2").text ("Bindings without maintainer(s) listed").end_tag ("h2");
		writer.start_tag ("p").text ("The general bindings maintainer is Evan Nemerson (IRC nickname: nemequ). If you would like to adopt some bindings, please contact him.").end_tag ("p");

		// writer.start_tag ("h2").text ("About documentation").end_tag ("h2");
		// writer.start_tag ("p").text ("Two types of documentation sources for bindings are supported: handwritten *.valadoc files and gir-files.").end_tag ("p");


		// index:
		writer.start_tag ("table", {"style", "width: 100%; margin: auto;"});

		writer.start_tag ("tr");
		writer.start_tag ("td", {"width", "10"}).end_tag ("td");
		writer.start_tag ("td", {"width", "20"}).end_tag ("td");
		writer.start_tag ("td").end_tag ("td");
		writer.start_tag ("td", {"width", "160"}).end_tag ("td");
		writer.start_tag ("td", {"width", "100"}).end_tag ("td");
		writer.start_tag ("td", {"width", "50"}).end_tag ("td");
		writer.start_tag ("td", {"width", "110"}).end_tag ("td");
		writer.start_tag ("td", {"width", "10"}).end_tag ("td");
		writer.end_tag ("tr");


		ArrayList<Package> packages = get_sorted_package_list ();
		char c = '\0';

		foreach (Package pkg in packages) {
			char local_c = pkg.name[0].toupper ();
			if (c != local_c) {
				writer.start_tag ("tr").start_tag ("td", {"colspan", "8"});
				writer.simple_tag ("hr", {"class", "main_hr"});
				writer.end_tag ("td").end_tag ("tr");

				writer.start_tag ("tr");
				writer.start_tag ("td", {"colspan", "3"}).start_tag ("h2", {"class", "main_title"}).text (local_c.to_string ()).text (":").end_tag ("h2").end_tag ("td");
				writer.start_tag ("td", {"style", "color:grey;font-style:italic;"}).text ("Documentation Source").end_tag ("td");
				writer.start_tag ("td", {"style", "color:grey;font-style:italic;"}).text ("Links:").end_tag ("td");
				writer.start_tag ("td", {"style", "color:grey;font-style:italic;"}).text ("Install:").end_tag ("td");
				writer.start_tag ("td", {"style", "color:grey;font-style:italic;"}).text ("Download:").end_tag ("td");
				writer.start_tag ("td").end_tag ("td");
				writer.end_tag ("tr");
				c = local_c;
			}

			//string maintainers = pkg.maintainers ?? "-";
			writer.start_tag ("tr", {"class", "highlight"});
			writer.start_tag ("td").end_tag ("td"); // space
			writer.start_tag ("td").simple_tag ("img", {"src", "/package.png"}).end_tag ("td");

			writer.start_tag ("td");
			if (pkg.is_deprecated) {
				writer.start_tag ("s").start_tag ("a", {"href", pkg.online_link}).text (pkg.name).end_tag ("a").end_tag ("s");
			} else {
				writer.start_tag ("a", {"href", pkg.online_link}).text (pkg.name).end_tag ("a");
			}

			if (pkg is ExternalPackage) {
				writer.simple_tag ("img", {"src", "/external_link.png"});
			}
			writer.end_tag ("td");

			writer.start_tag ("td", {"style", "white-space:no wrap"}).text (pkg.get_documentation_source ()).end_tag ("td");

			writer.start_tag ("td", {"style", "white-space:no wrap"});

			bool first = true;
			if (pkg.home != null) {
				writer.start_tag ("a", {"href", pkg.home}).text ("Home").end_tag ("a");
				first = false;
			}
			if (pkg.c_docs != null) {
				if (first == false) {
					writer.text (", ");
				}

				writer.start_tag ("a", {"href", pkg.c_docs}).text ("C-docs").end_tag ("a");
				first = false;
			}
			if (first == true) {
				writer.text ("-");
			}
			writer.end_tag ("td");
			

			string? install_link = pkg.get_catalog_file ();
			if (install_link != null) {
				string html_link = Path.build_filename (pkg.name, Path.get_basename (install_link));
				writer.start_tag ("td", {"style", "white-space:no wrap"}).start_tag ("a", {"href", html_link}).text ("Install").end_tag ("a").end_tag ("td");
				Valadoc.copy_file (install_link, Path.build_filename (output_directory, html_link));
			} else {
				writer.start_tag ("td", {"style", "white-space:no wrap"}).text ("-").end_tag ("td");
			}

			if (pkg.devhelp_link != null) {
				writer.start_tag ("td", {"style", "white-space:no wrap"}).start_tag ("a", {"href", pkg.devhelp_link}).text ("devhelp-package").end_tag ("a").end_tag ("td");
			} else {
				writer.start_tag ("td", {"style", "white-space:no wrap"}).text ("-").end_tag ("td");
			}

			writer.start_tag ("td").end_tag ("td"); // space
			writer.end_tag ("tr");
		}

		writer.end_tag ("table");
		writer.end_tag ("div");
		writer = null;
		file = null;
		try {
			copy_data ();
		} catch (Error e) {
			reporter.simple_error ("error: Can't copy data: %s", e.message);
		}
	}

	public void generate (string path) {
		stdout.printf ("generate index ...\n");

		generate_navigation (path + ".navi.tpl");
		generate_index (path + ".content.tpl");
	}

	public void regenerate_all_known_packages () throws Error {
		foreach (var pkg in packages_per_name.values) {
			if (pkg is ExternalPackage == false) {
				build_doc_for_package (pkg);
			}
		}
	}

	private string get_index_name (string pkg_name) {
		StringBuilder builder = new StringBuilder ();
		for (unowned string pos = pkg_name; pos.get_char () != '\0'; pos = pos.next_char ()) {
			unichar c = pos.get_char ();
			if (('A' <= c <= 'Z') || ('a' <= c <= 'z') || ('0' <= c <= '9')) {
				builder.append_unichar (c);
			}
		}

		return builder.str;
	}

	public void generate_configs (string path) throws Error {
		string constants_path = Path.build_filename (path, "constants.php");
		string path_prefix = Path.build_filename (path, "prefix.conf");

		var _prefix = FileStream.open (path_prefix, "w");
		_prefix.printf ("%s", prefix);

		var php = FileStream.open (constants_path, "w");
		bool first = true;

		php.printf ("<?php\n");
		php.printf ("\t$prefix = \"%s\";\n", prefix);
		php.printf ("\t$allpkgs = \"");
		foreach (Package pkg in packages_per_name.values) {
			if (pkg is ExternalPackage) {
				continue ;
			}

			if (first == false) {
				php.printf (",");
			}

			php.printf ("%s%s", prefix, get_index_name (pkg.name));
			first = false;
		}
		php.printf ("\";\n");
		php.printf ("?>\n");
	}

	/*
	public void generate_configs (string config_path) throws Error {
		string htaccess_path = Path.build_filename (config_path, ".htaccess");
		string sphinx_path = Path.build_filename (config_path, "sphinx.conf");
		string php_path = Path.build_filename (config_path, "constants.php");

		if (FileUtils.test (config_path, FileTest.EXISTS)) {
			FileUtils.unlink (htaccess_path);
			FileUtils.unlink (sphinx_path);
			FileUtils.unlink (php_path);
		}

		DirUtils.create (config_path, 0777);

		var php = FileStream.open (php_path, "w");
		php.printf ("<?php\n");
		php.printf ("\t$allpkgs = \"");


		var writer = FileStream.open (htaccess_path, "w");
		writer.printf ("Options -Indexes\n");
		writer.printf ("\n");
		writer.printf ("<Files ~ \"^\\.conf\">\n");
		writer.printf ("        Order allow,deny\n");
		writer.printf ("        Deny from all\n");
		writer.printf ("        Satisfy All\n");
		writer.printf ("</Files>\n");
		writer.printf ("\n\n");

		writer = FileStream.open (sphinx_path, "w");
		writer.printf ("searchd {\n");
		writer.printf ("        listen = 0.0.0.0:51413:mysql41\n");
		writer.printf ("        log = ./searchd.log\n");
		writer.printf ("        query_log = ./query.log\n");
		writer.printf ("        pid_file = ./searcd.pid\n");
		writer.printf ("}\n");

		writer.printf ("\n\n");

		writer.printf ("index base {\n");
		writer.printf ("        charset_type = utf-8\n");
		writer.printf ("        enable_star = 1\n");
		writer.printf ("        min_infix_len = 1\n");
		writer.printf ("        html_strip = 1\n");
		writer.printf ("        charset_table = 0..9, A..Z->a..z, ., _, a..z\n");
		writer.printf ("}\n");

		writer.printf ("source main {\n");
		writer.printf ("        type = xmlpipe2\n");
		writer.printf ("        xmlpipe_command = cat ../empty.xml\n");
		writer.printf ("}\n");

		writer.printf ("index main : base {\n");
		writer.printf ("        source = main\n");
		writer.printf ("        path = ./sphinx-main\n");
		writer.printf ("}\n");


		writer.printf ("\n\n");
		writer.printf ("\n\n");

		int startid = 0;

		foreach (var pkg in packages_per_name.values) {
			if (pkg is ExternalPackage == false) {
				string name = get_index_name (pkg.name);
				writer.printf ("source %s {\n", name);
				writer.printf ("        type = xmlpipe2\n");
				writer.printf ("        xmlpipe_command = xsltproc --stringparam startid %d ./sphinx.xsl ./../%s/index.xml\n", startid, pkg.name);
				writer.printf ("}\n");
				writer.printf ("\n\n");

				writer.printf ("index %s : base {\n", name);
				writer.printf ("        source = %s\n", name);
				writer.printf ("        path = ./sphinx-%s\n", name);
				writer.printf ("}\n");
				writer.printf ("\n\n");

				if (startid != 0) {
					php.printf (", ");
				}
				php.printf ("%s ", name);

				startid += 1000000;
			}
		}
		php.printf ("\";\n");
		php.printf ("?>\n");
	} */

	public void regenerate_packages (string[] packages) throws Error {
		LinkedList<Package> queue = new LinkedList<Package> ();

		foreach (string pkg_name in packages) {
			Package? pkg = packages_per_name.get (pkg_name);
			if (pkg == null) {
				reporter.simple_error ("error: Unknown package %s", pkg_name);
			}

			queue.add (pkg);
		}

		if (reporter.errors > 0) {
			return ;
		}

		foreach (Package pkg in queue) {
			build_doc_for_package (pkg);
		}
	}

	private void build_doc_for_package (Package pkg) throws Error {
		if (skip_existing && FileUtils.test (Path.build_filename (output_directory, pkg.name), FileTest.IS_DIR)) {
			return ;
		}

		StringBuilder builder = new StringBuilder ();
		builder.append_printf ("valadoc --driver \"%s\" --importdir girs --doclet \"%s\" -o \"tmp/%s\" \"%s\" --vapidir \"%s\" --girdir \"%s\" %s", driver, docletpath, pkg.name, pkg.get_vapi_path (), Path.get_dirname (pkg.get_vapi_path ()), girdir, pkg.flags);

		stdout.printf ("creating \'%s\' ...\n", pkg.name);

		string external_docu_path = pkg.get_valadoc_file ();
		if (external_docu_path != null) {
			stdout.printf ("  using .valadoc:        %s\n".printf (external_docu_path));

			builder.append_printf (" --importdir documentation/%s", pkg.name);
			builder.append_printf (" --import %s", pkg.name);
		}

		string gir_path = pkg.get_gir_file ();
		if (gir_path != null) {
			stdout.printf ("  using .gir:            %s\n", gir_path);
				
			builder.append_printf (" --importdir \"%s\"", girdir);
			builder.append_printf (" --import %s", pkg.gir_name);

			load_images (pkg);

			string metadata_path = pkg.get_gir_file_metadata_path ();
			if (metadata_path != null) {
				builder.append_printf (" --metadatadir %s", metadata_path);
			}
		}

		string wiki_path = "documentation/%s/index.valadoc".printf (pkg.name);
		if (FileUtils.test (wiki_path, FileTest.IS_REGULAR)) {
			stdout.printf ("  using .valadoc (wiki): documentation/%s/*.valadoc\n", pkg.name);

			builder.append_printf (" --wiki documentation/%s", pkg.name);
		}

		try {
			int exit_status = 0;
			string? standard_output = null;
			string? standard_error = null;

			Process.spawn_command_line_sync (builder.str, out standard_output, out standard_error, out exit_status); 

			FileStream log = FileStream.open ("LOG", "w");
			log.printf ("%s\n", builder.str);
			if (standard_error != null) {
				log.printf (standard_error);
			}
			if (standard_output != null) {
				log.printf (standard_output);
			}
			standard_output = null;
			standard_error = null;
			log = null;


			if (exit_status != 0) {
				throw new SpawnError.FAILED ("Exit status != 0");
			}

			Process.spawn_command_line_sync ("rm -r -f %s".printf (Path.build_path (Path.DIR_SEPARATOR_S, output_directory, pkg.name)));
			Process.spawn_command_line_sync ("mv LOG tmp/%s/%s".printf (pkg.name, pkg.name));
			Process.spawn_command_line_sync ("mv tmp/%s/%s \"%s\"".printf (pkg.name, pkg.name, output_directory)); 
		} catch (SpawnError e) {
			stdout.printf ("ERROR: Can't generate documentation for %s. See LOG for details.\n", pkg.name);
			throw e;
		}
	}

	private void collect_images (string content, HashSet<string> images) {
		Gtkdoc.Scanner scanner = new Gtkdoc.Scanner ();
		scanner.reset (content);

		for (Gtkdoc.Token token = scanner.next (); token.type != Gtkdoc.TokenType.EOF; token = scanner.next ()) {
			if (token.type == Gtkdoc.TokenType.XML_OPEN && (token.content == "inlinegraphic" || token.content == "graphic")) {
				if (token.attributes == null) {
					continue ;
				}

				string? link = token.attributes.get ("fileref");
				if (link != null) {
					images.add (link);
				}
			}
		}
	}

	private void load_images (Package pkg) {
		if (!download_images) {
			return ;
		}

		if (pkg.c_docs == null || pkg.gir_name == null) {
			return ;
		}

		string gir_path = pkg.get_gir_file ();

		stdout.printf ("  download images\n");

		var markup_reader = new Valadoc.MarkupReader (gir_path, reporter);
		MarkupTokenType token = MarkupTokenType.EOF;
		MarkupSourceLocation token_begin;
		MarkupSourceLocation token_end;

		HashSet<string> images = new HashSet<string> ();

		do {
			token = markup_reader.read_token (out token_begin, out token_end);

			if (token == MarkupTokenType.START_ELEMENT && markup_reader.name == "doc") {
				token = markup_reader.read_token (out token_begin, out token_end);
				if (token == MarkupTokenType.TEXT) {
					this.collect_images (markup_reader.content, images);
				}
			}
		} while (token != MarkupTokenType.EOF);

		foreach (string image_name in images) {
			try {
				string link = Path.build_path (Path.DIR_SEPARATOR_S, pkg.c_docs, image_name);
				Process.spawn_command_line_sync ("wget --directory-prefix documentation/%s/gir-images/ \"%s\"".printf (pkg.name, link));
			} catch (SpawnError e) {
			}
		}


		if (images.size > 0) {
			string metadata_file_path = "documentation/%s/%s.valadoc.metadata".printf (pkg.name, pkg.gir_name);
			if (!FileUtils.test (metadata_file_path, FileTest.EXISTS)) {
				FileStream stream = FileStream.open (metadata_file_path, "w");
				stream.printf ("\n");
				stream.printf ("[General]\n");
				stream.printf ("resources = gir-images/\n");
				stream.printf ("\n");
			}
		}
	}

	private void copy_data () throws FileError {
		Dir dir = Dir.open ("data");
		for (string? file = dir.read_name (); file != null; file = dir.read_name ()) {
			string src_file_path = Path.build_filename ("data", file);
			string dest_file_path = Path.build_filename (output_directory, file);
			Valadoc.copy_file (src_file_path, dest_file_path);
		}
	}

	public static int main (string[] args) {
		ErrorReporter reporter = new ErrorReporter ();

		try {
			var opt_context = new OptionContext ("- Vala Documentation Tool");
			opt_context.set_help_enabled (true);
			opt_context.add_main_entries (options, null);
			opt_context.parse (ref args);
		} catch (OptionError e) {
			stdout.printf ("error: %s", e.message);
			stdout.printf ("Run '%s --help' to see a full list of available command line options.\n", args[0]);
			return -1;
		}

		if (prefix == null) {
			stdout.printf ("error: prefix == null\n");
			return -1;
		}

		if (FileUtils.test (metadata_path, FileTest.IS_REGULAR)) {
			stdout.printf ("error: %s does not exist.\n", metadata_path);
			return -1;
		}

		if (FileUtils.test ("tmp", FileTest.IS_DIR)) {
			stdout.printf ("error: tmp already exist.\n");
			return -1;
		}

		if (output_directory == null) {
			output_directory = "valadoc.org";
		}

		string target_version = "0.16";

		if (driver == null) {
			driver = "%s.x".printf (target_version);
		}

		if (metadata_path == null) {
			metadata_path = "documentation/packages.xml";
		}

		if (docletpath == null) {
			docletpath = ".";
		}

		if (vapidir == null) {
			vapidir = "/usr/share/vala-%s/vapi/".printf (target_version);
		}


		if (!FileUtils.test (output_directory, FileTest.IS_DIR)) {
			if (DirUtils.create_with_parents (output_directory, 0777) != 0) {
				stdout.printf ("error: can't create output-directory: %s.\n", output_directory);
				return -1;
			}
		}

		if (DirUtils.create ("tmp", 0777) != 0) {
			stdout.printf ("error: can't create temp. directory.\n");
			return -1;
		}


		int return_val = 0;

		try {
			IndexGenerator generator = new IndexGenerator (reporter);
			generator.load_metadata (metadata_path);
			if (reporter.errors > 0) {
				return -1;
			}

			generator.load (output_directory);
			if (reporter.errors > 0) {
				return -1;
			}

			if (regenerate_all_packages) {
				generator.regenerate_all_known_packages ();
			} else {
				generator.regenerate_packages (requested_packages);
			}

			if (reporter.errors > 0) {
				return -1;
			}

			string index = Path.build_path (Path.DIR_SEPARATOR_S, output_directory, "index.htm");
			generator.generate (index);

			generator.generate_configs (output_directory);

			if (reporter.errors > 0) {
				return -1;
			}

		} catch (Error e) {
			return_val = -1;
		}

		try {
			Process.spawn_command_line_sync ("rm -r -f tmp");
		} catch (SpawnError e) {
		}

		return return_val;
	}
}

