(***********************************************************************)
(*                                                                     *)
(*                      The Cryptokit library                          *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 2002 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the GNU Library General Public License, with    *)
(*  the special exception on linking described in file LICENSE.        *)
(*                                                                     *)
(***********************************************************************)

(* $Id$ *)

(** The Cryptokit library provides a variety of cryptographic primitives
    that can be used to implement cryptographic protocols in
    security-sensitive applications.  The primitives provided include:
    - Symmetric-key cryptography: AES, DES, Triple-DES with 2 keys,
      ARCfour, in ECB, CBC, CFB and OFB modes.
    - Public-key cryptography: RSA.
    - Hash functions and MACs: SHA-1, MD5, and MACs based on AES and DES.
    - Random number generation.
    - Encodings and compression: base 64, hexadecimal, Zlib compression.

    To use this library, link with 
      [ocamlc unix.cma nums.cma cryptokit.cma]
    or
      [ocamlopt unix.cmxa nums.cmxa cryptokit.cmxa].
*)

(** {6 General-purpose abstract interfaces} *)

(** A <I>transform</I> is an arbitrary mapping from sequences of characters
    to sequences of characters.  Examples of transforms include
    ciphering, deciphering, compression, decompression, and encoding
    of binary data as text.  Input data to a transform is provided
    by successive calls to the methods [put_substring], [put_string],
    [put_char] or [put_byte].  The result of transforming the input
    data is buffered internally, and can be obtained via the
    [get_string], [get_substring], [get_char] and [get_byte] methods. *)
class type transform =
  object
    method put_substring: string -> int -> int -> unit
      (** [put_substring str pos len] processes [len] characters of
          string [str], starting at character number [pos],
          through the transform. *)
    method put_string: string -> unit
      (** [put_string str] processes all characters of string [str]
          through the transform. *)
    method put_char: char -> unit
      (** [put_char c] processes character [c] through the transform. *)
    method put_byte: int -> unit
      (** [put_byte b] processes the character having code [b]
          through the transform. [b] must be between [0] and [255]
          inclusive. *)
    method finish: unit
      (** Call method [finish] to indicate that no further data will
          be processed through the transform.  This causes the transform
          to e.g. add final padding to the data and flush its internal
          buffers.  Raise [Error Wrong_data_length] if the total length
          of input data provided via the [put_*] methods is not
          an integral number of the input block size
          (see {!transform#input_block_size}). After calling [finish],
          the transform can no longer accept additional data.  Hence,
          do not call any of the [put_*] methods after calling [finish]. *)
    method available_output: int
      (** Return the number of characters of output currently available.
          The output can be recovered with the [get_*] methods. *)
    method get_string: string
      (** Return a character string containing all output characters
          available at this point.  The internal output buffer is emptied;
          in other terms, all currently available output is consumed
          (and returned to the caller) by a call to [get_string]. *)
    method get_substring: string * int * int
      (** Return a triple [(buf,pos,len)], where [buf] is the internal
          output buffer for the transform, [pos] the position of the
          first character of available output, and [len] the number of
          characters of available output.  The string [buf] can be
          modified later, so the caller must immediately copy
          characters [pos] to [pos+len-1] of [buf] to some other
          location.  The internal output buffer is emptied;
          in other terms, all currently available output is consumed
          (and returned to the caller) by a call to [get_substring]. *)
    method get_char: char
      (** Return the first character of output, and remove it from the
          internal output buffer.  Raise [End_of_file] if no output
          is currently available. *)
    method get_byte: int
      (** Return the code of the first character of output,
          and remove it from the internal output buffer.
          Raise [End_of_file] if no output is currently available. *)
    method input_block_size: int
      (** Some transforms (e.g. unpadded block ciphers) process
          input data by blocks of several characters.  This method
          returns the size of input blocks for the current transform.
          If [input_block_size > 1], the user of the transform
          must ensure that the total length of input data provided
          between the creation of the cipher and the call to
          [finish] is an integral multiple of [input_block_size].
          If [input_block_size = 1], the transform can accept
          input data of arbitrary length. *)
    method output_block_size: int
      (** Some transforms (e.g. block ciphers) always produce output
          data by blocks of several characters.  This method
          returns the size of output blocks for the current transform.
          If [input_block_size > 1], the total length of output data
          produced by the transform is always an integral multiple
          of [output_block_size].
          If [output_block_size = 1], the transform produces output data
          of arbitrary length. *)
    method wipe: unit
      (** Erase all internal buffers and data structures of this transform,
          overwriting them with zeroes.  A transform may contain sensitive
          data such as secret key-derived material or parts of the
          input or output data.  Calling [wipe] ensures that this sensitive
          data will not remain in memory longer than strictly necessary,
          thus making certain invasive attacks more difficult.
          It is thus prudent practice to call [wipe] on every
          transform that the program no longer needs.
          After calling [wipe], the transform is no longer in a working
          state: do not call any other methods after calling [wipe]. *)
  end

val transform_string: transform -> string -> string
  (** [transform_string t s] runs the string [s] through the
      transform [t] and returns the transformed string.
      The transform [t] is wiped before returning, hence can
      no longer be used for further transformations. *)

val transform_channel:
       transform -> ?len:int -> in_channel -> out_channel -> unit
  (** [transform_channel ic oc] reads characters from input channel [ic],
      run them through the transform [t], and writes the transformed
      data to the output channel [oc].  If the optional [len] argument
      is provided, exactly [len] characters are read from [ic] and
      transformed; [End_of_file] is raised if [ic] does not contain
      at least [len] characters.  If [len] is not provided, [ic] is
      read all the way to end of file. 
      The transform [t] is wiped before returning, hence can
      no longer be used for further transformations. *)

val compose: transform -> transform -> transform
  (** Compose two transforms, feeding the output of the first transform
      to the input of the second transform. *)

(** A <I>hash</I> is a function that maps arbitrarily-long character
    sequences to small, fixed-size strings.  *)
class type hash =
  object
    method add_substring: string -> int -> int -> unit
      (** [add_substring str pos len] adds [len] characters from string
          [str], starting at character number [pos], to the running
          hash computation. *)
    method add_string: string -> unit
      (** [add_string str] adds all characters of string [str]
          to the running hash computation. *)
    method add_char: char -> unit
      (** [add_char c] adds character [c] to the running hash computation. *)
    method add_byte: int -> unit
      (** [add_byte b] adds the character having code [b]
          to the running hash computation.  [b] must be between [0] and [255]
          inclusive. *)
    method result: string
      (** Terminate the hash computation and return the hash value for
          the input data provided via the [add_*] methods.  The hash
          value is a string of length [hash_size] characters.
          After calling [result], the hash can no longer accept
          additional data.  Hence, do not call any of the [add_*] methods
          after [result]. *)
    method hash_size: int
      (** Return the size of hash values produced by this hash function,
          in characters. *)
    method wipe: unit
      (** Erase all internal buffers and data structures of this hash,
          overwriting them with zeroes.  See {!transform#wipe}. *)
  end

val hash_string: hash -> string -> string
  (** [hash_string h s] runs the string [s] through the hash function [h]
      and returns the hash value of [s].  
      The hash [h] is wiped before returning, hence can
      no longer be used for further hash computations. *)
val hash_channel: hash -> ?len:int -> in_channel -> string
  (** [hash_channel h ic] reads characters from the input channel [ic],
      compute their hash value and return it.
      If the optional [len] argument is provided, exactly [len] characters
      are read from [ic] and hashed; [End_of_file] is raised if [ic]
      does not contain at least [len] characters.
      If [len] is not provided, [ic] is read all the way to end of file.      
      The hash [h] is wiped before returning, hence can
      no longer be used for further hash computations. *)

(** {6 Utilities: random numbers and padding schemes} *)

(** The [Random] module provides (pseudo-) random number generators
    suitable for generating cryptographic keys, nonces, or challenges. *)
module Random : sig

  class type rng =
    object
      method random_bytes: string -> int -> int -> unit
        (** [random_bytes buf pos len] stores [len] random bytes
            in string [buf], starting at position [pos]. *)
      method wipe: unit
        (** Erases the internal state of the generator.
            Do not call [random_bytes] after calling [wipe]. *)
    end
    (** Generic interface for a random number generator. *)

  val string: rng -> int -> string
    (** [random_string rng len] returns a string of [len] random bytes
        read from the generator [rng]. *)

  val secure_rng: rng
    (** A high-quality random number generator, using hard-to-predict
        system data to generate entropy.  This generator reads from
        [/dev/random] on systems that supports it, or interrogate
        the EGD daemon otherwise (see [http://egd.sourceforge.net/]).
        For EGD, the following paths are tried to locate the Unix socket
        used to communicate with EGD:
        - the value of the environment variable [EGD_SOCKET];
        - [$HOME/.gnupg/entropy];
        - [/var/run/egd-pool]; [/dev/egd-pool]; [/etc/egd-pool].

        [secure_rng#random_bytes] fails
        if neither [/dev/random] nor EGD are available.
        [secure_rng#random_bytes] may block until enough entropy
        has been gathered.  Do not use for generating large quantities
        of random data, else you might exhaust the entropy sources
        of the system. *)

  class device_rng: string -> rng
    (** [new device_rng devicename] returns a random number generator
        that reads from the special file [devicename], e.g.
        [/dev/random] or [/dev/urandom]. *)

  class egd_rng: string -> rng
    (** [new device_rng egd_socket] returns a random number generator
        that uses the Entropy Gathering Daemon ([http://egd.sourceforge.net/]).
        [egd_socket] is the path to the Unix socket that EGD uses for
        communication.  *)

  class pseudo_rng: string -> rng
    (** [new pseudo_rng seed] returns a pseudo-random number generator
        seeded by the string [seed].  [seed] must contain at least
        16 characters, and can be arbitrarily longer than this,
        except that only the first 55 characters are used.
        Technically, the first 16 characters of [seed] are used as
        a key for the AES cipher in CBC mode, which encrypts the output
        of a lagged Fibonacci generator [X(i) = (X(i-24) + X(i-55)) mod 256]
        seeded with the first 55 characters of [seed].
        While this generator is believed to have good statistical properties,
        it still does not generate ``true'' randomness: the entropy of
        the strings it creates cannot exceed the entropy contained in
        the seed.  As a typical use,
        [new Random.pseudo_rng (Random.string Random.secure_rng 20)] returns a
        generator that can generate arbitrarily long strings of pseudo-random
        data without delays, and with a total entropy of approximately
        160 bits. *)
end        

(** To apply block ciphers to input data of arbitrary length, it is
    required to pad the input data to an integral multiple of the
    block size, by adding conventional characters at the end.
    The padding characters are then stripped when the ciphertext is
    decrypted.  The [Padding] module defines a generic interface
    for padding schemes, as well as two popular padding schemes. *)
module Padding : sig

  class type scheme =
    object
      method pad: string -> int -> unit
        (** [pad str used] is called with a buffer string [str]
            containing valid input data at positions [0, ..., used-1].
            The [pad] method must write padding characters in positions
            [used] to [String.length str - 1].  It is guaranteed that
            [used < String.length str], so that at least one character of
            padding must be added.  The padding scheme must be unambiguous
            in the following sense: from [buf] after padding, it must be
            possible to determine [used] unambiguously.  (This is what
            method {!strip} does.) *)
      method strip: string -> int
        (** This is the converse of the [pad] operation: from a padded
            string [buf] as built by method [pad], [strip buf] determines
            and returns the starting position of the padding data,
            or equivalently the length of valid, non-padded input data
            in [buf].  This method must raise [Error Bad_padding] if
            [buf] does not have the format of a padded block as produced
            by [pad]. *)
    end
    (** Generic interface of a padding scheme. *)

  val length: scheme
    (** This padding scheme pads data with [n] copies of the character
        having code [n].  It is unambiguous since at least one
        character of padding is added.  This scheme is defined in RFC 2040. *)
  val _8000: scheme
    (** This padding scheme pads data with one [0x80] byte, followed
        by as many [0] bytes as needed to fill the block. *)
end

(** {6 Cryptographic primitives (simplified interface)} *)

(** The [Cipher] module implements the AES, DES, Triple-DES and ARCfour
    symmetric ciphers.  Symmetric ciphers are presented as transforms
    parameterized by a secret key and a ``direction'' indicating
    whether encryption or decryption is to be performed.  
    The same secret key is used for encryption and for decryption. *)
module Cipher : sig

  type direction = Encrypt | Decrypt
    (** Indicate whether the cipher should perform encryption
        (transforming plaintext to ciphertext) or decryption
        (transforming ciphertext to plaintext). *)

  type chaining_mode =
      ECB
    | CBC
    | CFB of int
    | OFB of int
    (** Block ciphers such as AES or DES map a fixed-sized block of
        input data to a block of output data of the same size.
        A chaining mode indicates how to extend them to multiple blocks
        of data.  The four chaining modes supported in this library are:
        - [ECB]: Electronic Code Book mode.
        - [CBC]: Cipher Block Chaining mode.
        - [CFB n]:  Cipher Feedback Block with [n] bytes.
        - [OFB n]: Output Feedback Block with [n] bytes.

        A detailed description of these modes is beyond the scope of
        this documentation; refer to a good cryptography book.
        [CBC] is a recommended default.  For [CFB n] and [OFB n],
        note that the blocksize is reduced to [n], but encryption
        speed drops by a factor of [blocksize / n], where [blocksize]
        is the block size of the underlying cipher; moreover, [n]
        must be between [1] and [blocksize] included. *)

  val aes: ?mode:chaining_mode -> ?pad:Padding.scheme -> ?iv:string ->
             string -> direction -> transform
    (** AES is the Advanced Encryption Standard, also known as Rijndael.
        This is a modern block cipher, recently standardized.
        It has 128 bit keys and process data by blocks of 128 bits (16 bytes).
        The string argument is the key; it must have length 16.
        The direction argument specifies whether encryption or decryption
        is to be performed.

        The optional [mode] argument specifies a
        chaining mode, as described above; [CBC] is used by default.

        The optional [pad] argument specifies a padding scheme to
        pad cleartext to an integral number of blocks.  If no [pad]
        argument is given, no padding is performed and the length
        of the cleartext must be an integral number of blocks.

        The optional [iv] argument is the initialization vector used
        in modes CBC, CFB and OFB.  It is ignored in ECB mode.
        If provided, it must be a string of the same size as the block size
        (16 bytes).  If omitted, the null initialization vector
        (16 zero bytes) is used.

        The [aes] function returns a transform that performs encryption
        or decryption, depending on the direction argument. *)

  val des: ?mode:chaining_mode -> ?pad:Padding.scheme -> ?iv:string ->
             string -> direction -> transform
    (** DES is the Digital Encryption Standard.  Standardized in 1972,
        this is probably still the most widely used cipher today.
        It resisted 30 years of cryptanalysis, but can be broken
        relatively easily by brute force, due to its small key size (56 bits).
        It should therefore be considered as weak encryption.
        Its block size is 64 bits (8 bytes).
        The arguments to the [des] function have the same meaning as
        for the {!aes} function.  The key argument is a string of
        length 8 (64 bits); the most significant bit of each key byte
        is ignored. *)

  val triple_des: ?mode:chaining_mode -> ?pad:Padding.scheme -> ?iv:string ->
             string -> direction -> transform
    (** Triple DES with two DES keys.  This is a popular variant of DES
        where each block is encrypted with a 56-bit key [k1],
        decrypted with another 56-bit key [k2], then re-encrypted
        with [k1].  This results in a 112-bit key length that resists
        brute-force attacks.  However, the three encryptions required
        on each block make this cipher quite slow (4 times slower than AES).
        The arguments to the [triple_des] function have the same meaning as
        for the {!aes} function.  The key argument is a string of
        length 16 (128 bits), representing the concatenation of the
        two key halves [k1] and [k2].  The most significant bit of
        each key byte is ignored. *)

  val arcfour: string -> direction -> transform
    (** ARCfour (``alleged RC4'') is a fast stream cipher
        that appears to produce equivalent results with the commercial
        RC4 cipher from RSA Data Security Inc.  This company holds the
        RC4 trademark, and sells the real RC4 cipher.  So, it is prudent
        not to use ARCfour in a commercial product.  The ARCfour cipher
        operates on bytes, not blocks, hence no padding is required.
        It accepts any key length up to 2048 bits, although the
        present implementation is limited to 128 bits, to comply with
        French regulations.  Encryption is fast -- approximately 2 times
        faster than AES.  However, this is a stream cipher: 
        the xor of two ciphertexts obtained with the same key
        is the xor of the corresponding plaintexts, which allows various
        attacks.  Hence, the same key must never be reused.
        The string argument is the key; it can have any length between 0
        and 16 (the longer the better, of course).
        The direction argument is present for consistency with the other
        ciphers only, and is actually ignored: like all stream ciphers,
        decryption is the same function as encryption. *)
end

(** The [Hash] module implements unkeyed cryptographic hashes, also
    known as message digest functions.  Hash functions used in
    cryptography are characterized as being <I>one-way</I>
    (given a hash value, it is computationally infeasible to find
    a text that hashes to this value) and <I>collision-resistant</I>
    (it is computationally infeasible to find two different texts
    that hash to the same value).  Thus, the hash of a text can be
    used as a compact replacement for this text for the purposes of
    ensuring integrity of the text.

    Two hash functions are provided in module [Hash]: SHA-1 and MD5. *)
module Hash : sig
  val sha1: unit -> hash
    (** SHA-1 is the Secure Hash Algorithm revision 1.  It is a NIST
        standard, is widely used, and has no known weaknesses.
        It produces 160-bit hashes (20 bytes).  *)
  val md5: unit -> hash
    (** MD5 is an older hash function, producing 128-bit hashes (16 bytes).
        While popular in many applications, it is considered as
        potentially slightly weaker than SHA-1. *)
end

(** The [MAC] module implements message authentication codes, also
    known as keyed hash functions.  These are hash functions parameterized
    by a secret key.  In addition to being one-way and collision-resistant,
    a MAC has the property that without knowing the secret key, it is
    computationally infeasible to find the hash for a known text,
    even if many pairs of (text, MAC) are known to the attacker.
    Thus, MAC can be used to authenticate the sender of a text:
    the receiver of a (text, MAC) pair can recompute the MAC from the text,
    and if it matches the transmitted MAC, be reasonably certain that
    the text was authentified by someone who possesses the secret key.

    The module [MAC] provides one MAC function based on SHA-1,
    and three MAC functions based on the block ciphers
    AES, DES, and Triple-DES. *)
module MAC: sig
  val sha1: string -> hash
    (** [sha1 key] returns a MAC that uses SHA-1 as follows:
        the MAC of text [x] is [H(key ^ pad1 ^ H(key ^ pad2 ^ x))]
        where [H] is SHA-1, and [pad1] and [pad2] extend [key] to an
        integral number of 64-byte blocks.  ([pad1] uses zeroes and
        [pad2] uses [0xFF] bytes.)  Many similar constructions of
        a MAC from an unkeyed hash function are possible; this one
        is recommended in the Handbook of Applied Cryptography.
        The returned hash values are 160-bit long (20 bytes).
        The key argument can have arbitrary length, but must not
        be too small (e.g. less than 8 bytes) because of
        brute-force attacks. *)
  val aes: ?iv:string -> ?pad:Padding.scheme -> string -> hash
    (** [aes key] returns a MAC based on AES encryption in CBC mode.
        The ciphertext is discarded, except the last ciphertext block,
        which is the MAC value.  Thus, the returned hash values
        are 128 bit (16 bytes) long.  The [key] argument is the
        MAC key; it must have length 16 (128 bits).
        The optional [iv] argument is the first value of the
        initialization vector, and defaults to 0.  The optional [pad]
        argument specifies a padding scheme to pad input to an
        integral number of 16-byte blocks. *)
  val des: ?iv:string -> ?pad:Padding.scheme -> string -> hash
    (** [des key] returns a MAC based on DES encryption in CBC mode.
        The construction is identical to that used for the [aes] MAC.
        The key size is 64 bits (8 bytes), of which only 56 are used.
        The returned hash value has length 8 bytes.
        Due to the small hash size and key size, this MAC is rather weak;
        use AES or Triple-DES if at all possible. *)
  val triple_des: ?iv:string -> ?pad:Padding.scheme -> string -> hash
    (** [des key] returns a MAC based on triple DES encryption with
        two keys in CBC mode.
        The construction is identical to that used for the [aes] MAC.
        The key size is 128 bits (16 bytes), of which only 112 are used.
        The returned hash value has length 8 bytes.
        The key size is sufficient to protect against brute-force attacks,
        but the small hash size means that this MAC is not 
        collision-resistant. *)
end

(** The [RSA] module implements RSA public-key cryptography.
    Public-key cryptography is asymmetric: two distinct keys are used
    for encrypting a message, then decrypting it.  Moreover, while one of
    the keys must remain secret, the other can be made public, since
    it is computationally very hard to reconstruct the private key
    from the public key.   This feature supports both public-key
    encryption (anyone can encode with the public key, but only the
    owner of the private key can decrypt) and digital signature
    (only the owner of the private key can sign, but anyone can check
    the signature with the public key). *)
module RSA: sig

  type key =
    { size: int;    (** Size of the modulus [n], in bits *)
      n: string;    (** Modulus [n = p.q] *)
      e: string;    (** Public exponent [e] *)
      d: string;    (** Private exponent [d] *)
      p: string;    (** Prime factor [p] of [n] *)
      q: string;    (** The other prime factor [q] of [n] *)
      dp: string;   (** [dp] is [d mod (p-1)] *)
      dq: string;   (** [dq] is [d mod (q-1)] *)
      qinv: string  (** [qinv] is a multiplicative inverse of [q] modulo [p] *)
    }
    (** The type of RSA keys.  Components [size], [n] and [e] define
        the public part of the key.  Components [size], [n] and [d]
        define the private part of the key.  To speed up secret key operations
        through the use of the Chinese remainder theorem (CRT), additional
        components [p], [q], [dp], [dq] and [qinv] are provided.  These
        are part of the secret key. *)

  val wipe_key: key -> unit
    (** Erase all components of a RSA key. *)

  val new_key: ?rng: Random.rng -> ?e: int -> int -> key
    (** Generate a new, random RSA key.  The non-optional [int] argument
        is the desired size for the modulus, in bits (e.g. 1024).
        The optional [rng] argument specifies a random number generator
        to use for generating the key; it defaults to {!Random.secure_rng}.
        The optional [e] argument specifies the public exponent desired.
        If not specified, [e] is chosen randomly.
        Some standards mandate [e = 3] or [e = 65537].  While [e = 3]
        is known to weaken RSA, [e = 65537] significantly 
        speeds up encryption and signature checking compared with a
        random [e], without impacting security.
        The result of [new_key] is a complete RSA key with all components
        defined: public, private, and private for use with the CRT. *)

  val encrypt: key -> string -> string
    (** [encrypt k msg] encrypts the string [msg] with the public part
        of key [k] (components [n] and [e]).
        [msg] must be smaller than [key.n] when both strings
        are viewed as natural numbers in big-endian notation.
        In practice, [msg] should be of length [key.size / 8 - 1],
        using padding if necessary.  If you need to encrypt longer plaintexts
        using RSA, encrypt them with a symmetric cipher, using a
        randomly-generated key, and encrypt only that key with RSA. *)
  val decrypt: key -> string -> string
    (** [decrypt k msg] decrypts the ciphertext string [msg] with the
        private part of key [k] (components [n] and [d]).
        The size of [msg] is limited as described for {!encrypt}. *)
  val decrypt_CRT: key -> string -> string
    (** [decrypt_CRT k msg] decrypts the ciphertext string [msg] with the
        CRT private part of key [k] (components [n], [p], [q], [dp], [dq]
        and [qinv]).  The use of the Chinese remainder theorem (CRT)
        allows significantly faster decryption than {!decrypt}, at no
        loss in security. 
        The size of [msg] is limited as described for {!encrypt}. *)
  val sign: key -> string -> string
    (** [sign k msg] encrypts the plaintext string [msg] with the
        private part of key [k] (components [n] and [d]), thus
        performing a digital signature on [msg].
        The size of [msg] is limited as described for {!encrypt}.
        If you need to sign longer messages, compute a cryptographic
        hash of the message and sign only the hash with RSA. *)
  val sign_CRT: key -> string -> string
    (** [sign_CRT k msg] encrypts the plaintext string [msg] with the
        CRT private part of key [k] (components [n], [p], [q], [dp], [dq]
        and [qinv]), thus performing a digital signature on [msg].
        The use of the Chinese remainder theorem (CRT)
        allows significantly faster signature than {!sign}, at no
        loss in security. 
        The size of [msg] is limited as described for {!encrypt}. *)
  val unwrap_signature: key -> string -> string
    (** [unwrap_signature k msg] decrypts the ciphertext string [msg]
        with the public part of key [k] (components [n] and [d]),
        thus extracting the plaintext that was signed by the sender.
        The size of [msg] is limited as described for {!encrypt}. *)
end

(** {6 Advanced, compositional interface to block ciphers 
       and stream ciphers} *)

(** The [Block] module provides classes that implements
    popular block ciphers, chaining modes, and wrapping of a block cipher
    as a general transform.  The classes can be composed in a Lego-like
    fashion, facilitating the integration of new block ciphers, modes, etc. *)
module Block : sig

  class type block_cipher =
    object
      method blocksize: int
        (** The size in bytes of the blocks manipulated by the cipher. *)
      method transform: string -> int -> string -> int -> unit
        (** [transform src spos dst dpos] encrypts or decrypts one block
            of data.  The input data is read from string [src] at
            positions [spos, ..., spos + blocksize - 1], and the output
            data is stored in string [dst] at positions
            [dpos, ..., dpos + blocksize - 1]. *)
      method wipe: unit
        (** Erase the internal state of the block cipher, such as
            all key-dependent material. *)
    end
      (** Abstract interface for a block cipher. *)

  class cipher: block_cipher -> transform
    (** Wraps a block cipher as a general transform.  The transform
        has input block size and output block size equal to the
        block size of the block cipher.  No padding is performed.
        Example: [new cipher (new cbc_encrypt (new aes_encrypt key))]
        returns a transform that performs AES encryption in CBC mode. *)
  class cipher_padded_encrypt: Padding.scheme -> block_cipher -> transform
    (** Like {!cipher}, but performs padding on the input data
        as specified by the first argument.  The input block size of
        the returned transform is 1; the output block size is the
        block size of the block cipher. *)
  class cipher_padded_decrypt: Padding.scheme -> block_cipher -> transform
    (** Like {!cipher}, but removes padding on the output data
        as specified by the first argument.  The output block size of
        the returned transform is 1; the input block size is the
        block size of the block cipher. *)
  class mac: ?iv: string -> ?pad: Padding.scheme -> block_cipher -> hash
    (** Build a MAC (keyed hash function) from the given block cipher.
        The block cipher is run in CBC mode, and the MAC value is
        the last ciphertext block.  Thus, the hash size of the resulting
        hash is the block size of the block cipher.
        The optional argument [iv] specifies the initialization
        vector, with a default of all zeroes.  The optional argument
        [pad] specifies a padding scheme to be applied to the input
        data; if not provided, no padding is performed. *)

  class aes_encrypt: string -> block_cipher
    (** The AES block cipher, in encryption mode.  The string argument
        is the key; its length must be 16 bytes. *)
  class aes_decrypt: string -> block_cipher
    (** The AES block cipher, in decryption mode. *)

  class des_encrypt: string -> block_cipher
    (** The DES block cipher, in encryption mode.  The string argument
        is the key; its length must be 8 bytes. *)
  class des_decrypt: string -> block_cipher
    (** The DES block cipher, in decryption mode. *)

  class triple_des_encrypt: string -> block_cipher
    (** The Triple-DES-with-two-keys block cipher, in encryption mode.
        The key argument must have length 16. *)
  class triple_des_decrypt: string -> block_cipher
    (** The Triple-DES-with-two-keys block cipher, in decryption mode. *)

  class cbc_encrypt: ?iv: string -> block_cipher -> block_cipher
    (** Add Cipher Block Chaining (CBC) to the given block cipher
        in encryption mode.
        Each block of input is xor-ed with the previous output block
        before being encrypted through the given block cipher.
        The optional [iv] argument specifies the string to be xor-ed
        with the first input block, and defaults to all zeroes.
        The returned block cipher has the same block size as the
        underlying block cipher. *)
  class cbc_decrypt: ?iv: string -> block_cipher -> block_cipher
    (** Add Cipher Block Chaining (CBC) to the given block cipher
        in decryption mode.  This works like {!cbc_encrypt}, 
        except that input blocks are first decrypted by the block
        cipher before being xor-ed with the previous input block. *)

  class cfb_encrypt: ?iv: string -> int -> block_cipher -> block_cipher
    (** Add Cipher Feedback Block (CFB) to the given block cipher
        in encryption mode.  The integer argument [n] is the number of
        bytes processed at a time; it must lie between [1] and
        the block size of the underlying cipher, included.
        The returned block cipher has block size [n]. *)
  class cfb_decrypt: ?iv: string -> int -> block_cipher -> block_cipher
    (** Add Cipher Feedback Block (CFB) to the given block cipher
        in decryption mode.  See {!cfb_encrypt}. *)
  class ofb: ?iv: string -> int -> block_cipher -> block_cipher
    (** Add Output Feedback Block (OFB) to the given block cipher.
        The integer argument [n] is the number of
        bytes processed at a time; it must lie between [1] and
        the block size of the underlying cipher, included.        
        The returned block cipher has block size [n].
        It is usable both for encryption and decryption. *)
end

(** The [Stream] module provides classes that implement
    the ARCfour stream cipher, and the wrapping of a stream cipher
    as a general transform. The classes can be composed in a Lego-like
    fashion, facilitating the integration of new stream ciphers. *)
module Stream : sig

  class type stream_cipher =
    object
      method transform: string -> int -> string -> int -> int -> unit
        (** [transform src spos dst dpos len] encrypts or decrypts
            [len] characters, read from string [src] starting at
            position [spos].  The resulting [len] characters are
            stored in string [dst] starting at position [dpos]. *)
      method wipe: unit
        (** Erase the internal state of the stream cipher, such as
            all key-dependent material. *)
    end
      (** Abstract interface for a stream cipher. *)

  class cipher: stream_cipher -> transform
    (** Wraps an arbitrary stream cipher as a transform.
        The transform has input and output block size of 1. *)

  class arcfour: string -> stream_cipher
    (** The ARCfour (``alleged RC4'') stream cipher.
        The argument is the key, and must be of length 16 or less.
        This stream cipher works by xor-ing the input with the
        output of a key-dependent pseudo random number generator.
        Thus, decryption is the same function as encryption. *)
end

(** {6 Encoding and compression of data} *)

(** The [Base64] module supports the encoding and decoding of
    binary data in base 64 format, using only alphanumeric
    characters that can safely be transmitted over e-mail or
    in URLs. *)
module Base64: sig
  val encode_multiline : unit -> transform
    (** Return a transform that performs base 64 encoding.
        The output is divided in lines of length 76 characters,
        and final [=] characters are used to pad the output,
        as specified in the MIME standard. 
        The output is approximately [4/3] longer than the input. *)
  val encode_compact : unit -> transform
    (** Same as {!encode_multiline}, but the output is not
        split into lines, and no final padding is added.
        This is adequate for encoding short strings for
        transmission as part of URLs, for instance. *)
  val decode : unit -> transform
    (** Return a transform that performs base 64 decoding.
        The input must consist of valid base 64 characters;
        blanks are ignored.  Raise [Error Bad_encoding]
        if invalid base 64 characters are encountered in the input. *)
end

(** The [Hexa] module supports the encoding and decoding of
    binary data as hexadecimal strings.  This is a popular format
    for transmitting keys in textual form. *)
module Hexa: sig
  val encode : unit -> transform
    (** Return a transform that encodes its input in hexadecimal.
        The output is twice as long as the input, and contains
        no spaces or newlines. *)
  val decode : unit -> transform
    (** Return a transform that decodes its input from hexadecimal.
        The output is twice as short as the input.  Blanks
        (spaces, tabs, newlines) in the input are ignored.
        Raise [Error Bad_encoding] if the input contains characters
        other than hexadecimal digits and blanks. *)
end

(** The [Zlib] module supports the compression and decompression
    of data, using the [zlib] library: Lempel-Ziv compression
    as used by the [gzip] and [zip] compressors.   While compression
    itself is not encryption, it is often used prior to encryption
    to hide regularities in the plaintext, and reduce the size of
    the ciphertext. *)
module Zlib: sig
  val compress : ?level:int -> unit -> transform
    (** Return a transform that compresses its input.
        The optional [level] argument is an integer between 1 and 9
        specifying how hard the transform should try to compress data:
        1 is lowest but fastest compression, while 9 is highest but
        slowest compression. The default level is 7. *)
  val uncompress : unit -> transform
    (** Return a transform that decompresses its input. *)
end

(** {6 Error reporting} *)

(** Error codes for this library. *)
type error =
    Compression_error of string * string
      (** Error during compression or decompression. *)
  | Wrong_key_size
      (** The key is too long or too short for the given cipher. *)
  | Wrong_IV_size
      (** The initialization vector does not have the same size as
          the block size. *)
  | Wrong_data_length
      (** The total length of the input data for a transform is not an
          integral multiple of the input block size. *)
  | Bad_padding
      (** Incorrect padding bytes were found after decryption. *)
  | Output_buffer_overflow
      (** The output buffer for a transform exceeds the maximal length
          of a Caml string. *)
  | Number_too_long
      (** Denotes an internal error in RSA key generation or encryption. *)
  | Seed_too_short
      (** The seed given to a pseudo random number generator is too short. *)
  | Message_too_long
      (** The message passed to RSA encryption or decryption is greater
          than the modulus of the RSA key *)
  | Bad_encoding
      (** Illegal characters were found in an encoding of binary data
          such as base 64 or hexadecimal. *)
  | No_entropy_source
      (** No entropy source ([/dev/random] or EGD) was found for
          {!Random.secure_rng}. *)
  | Entropy_source_closed
      (** End of file on a device or EGD entropy source. *)

exception Error of error
  (** Exception raised by functions in this library
      to report error conditions. *)

(** {6 Miscellaneous utilities} *)

val wipe_string : string -> unit
    (** [wipe_string s] overwrites [s] with zeroes.  Can be used
        to reduce the memory lifetime of sensitive data. *)
val xor_string: string -> int -> string -> int -> int -> unit
    (** [xor_string src spos dst dpos len] performs the xor (exclusive or)
        of characters [spos, ..., spos + len - 1] of [src]
        with characters [dpos, ..., dpos + len - 1] of [dst],
        storing the result in [dst] starting at position [dpos]. *)
