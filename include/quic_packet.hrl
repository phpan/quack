-ifndef(QUIC_PACKET_HRL).
-define(QUIC_PACKET_HRL, included).

-include("quic_data_kv.hrl").
-include("quic_frame.hrl").
-include("quic_numeric.hrl").

-record(public_flags, {
          version :: 0 | 1,
          reset :: 0 | 1,
          diversification_nonce :: 0 | 1,
          connection_id :: 0 | 1,
          packet_number_encoding :: 0 | 1 | 2 | 3
         }).

-record(public_reset_packet, {
          connection_id :: connection_id(),
          tagged_values :: tagged_values()
         }).
-type public_reset_packet() :: #public_reset_packet{}.

-record(version_negotiation_packet, {
          connection_id :: connection_id(),
          supported_versions :: [binary(), ...]
         }).
-type version_negotiation_packet() :: #version_negotiation_packet{}.

-record(inbound_regular_packet, {
          connection_id :: connection_id(),   % optional
          version :: binary(),                % optional
          diversification_nonce :: binary(),  % optional
          packet_number :: packet_number(),   % optional
          frames :: [frame()]                 % optional
         }).
-type inbound_regular_packet() :: #inbound_regular_packet{}.

-record(outbound_regular_packet, {
          connection_id :: connection_id(),   % optional
          version :: binary(),                % optional
          diversification_nonce :: binary(),  % optional
          packet_number :: packet_number(),   % optional
          frames :: [frame()],                % optional
          crypto_state :: current | quic_crypto:state() % optional
         }).
-type outbound_regular_packet() :: #outbound_regular_packet{}.

-type quic_packet() :: (public_reset_packet() |
                        version_negotiation_packet() |
                        inbound_regular_packet() |
                        outbound_regular_packet()).

-type connection_id() :: uint64().
-type packet_number() :: uint48().

-endif.
