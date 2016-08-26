-module(quic_frame).

-include("quic_frame.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([append_padding_to_encoded_frames/3]).
-export([decode_frames/2]).
-export([encode_frames/2]).

%% ------------------------------------------------------------------
%% Padding
%% ------------------------------------------------------------------

append_padding_to_encoded_frames(EncodedFrames, MissingSize, PacketNumberEncoding) when MissingSize > 0 ->
    [EncodedFrames, encode_frame(#padding_frame{ size = MissingSize - 1 }, PacketNumberEncoding)].

%% ------------------------------------------------------------------
%% Frame sequence decoding
%% ------------------------------------------------------------------

decode_frames(<<>>, _PacketNumberEncoding) ->
    [];
decode_frames(<<1:1,
                FinBit:1,
                DataLengthBit:1,
                OffsetHeaderEncoding:3,
                StreamIdEncoding:2,
                Data/binary>>,
              PacketNumberEncoding) ->
    % Stream frame (special)
    {RemainingData, Frame} = quic_frame_stream:decode(Data, FinBit, DataLengthBit,
                                                      OffsetHeaderEncoding,
                                                      StreamIdEncoding),
    [Frame | decode_frames(RemainingData, PacketNumberEncoding)];
decode_frames(<<0:1,
                1:1,
                MultipleAckRangesBit:1,
                _:1, % unused
                LargestAckedEncoding:2,
                AckBlockEncoding:2,
                Data/binary>>,
              PacketNumberEncoding) ->
    % ACK frame (special)
    {RemainingData, Frame} = quic_frame_ack:decode(Data, MultipleAckRangesBit,
                                                   LargestAckedEncoding,
                                                   AckBlockEncoding),
    [Frame | decode_frames(RemainingData, PacketNumberEncoding)];
%decode_frames(<<0:2,
%                1:1,
%                _:5, % unused,
%                _/binary>>) ->
%    % Congestion feedback (special - unspecified yet)
%    exit({unspecified, congestion_feedback});
decode_frames(<<2#00000000:8, Data/binary>>, PacketNumberEncoding) ->
    % Padding frame
    {RemainingData, Frame} = decode_padding_frame(Data),
    [Frame | decode_frames(RemainingData, PacketNumberEncoding)];
decode_frames(<<2#00000001:8, Data/binary>>, PacketNumberEncoding) ->
    % Reset stream frame
    {RemainingData, Frame} = decode_reset_stream_frame(Data),
    [Frame | decode_frames(RemainingData, PacketNumberEncoding)];
decode_frames(<<2#00000010:8, Data/binary>>, PacketNumberEncoding) ->
    % Connection close frame
    {RemainingData, Frame} = decode_connection_close_frame(Data),
    [Frame | decode_frames(RemainingData, PacketNumberEncoding)];
decode_frames(<<2#00000011:8, Data/binary>>, PacketNumberEncoding) ->
    % Go away frame
    {RemainingData, Frame} = decode_go_away_frame(Data),
    [Frame | decode_frames(RemainingData, PacketNumberEncoding)];
decode_frames(<<2#00000100:8, Data/binary>>, PacketNumberEncoding) ->
    % Window update frame
    {RemainingData, Frame} = decode_window_update_frame(Data),
    [Frame | decode_frames(RemainingData, PacketNumberEncoding)];
decode_frames(<<2#00000101:8, Data/binary>>, PacketNumberEncoding) ->
    % Blocked frame
    {RemainingData, Frame} = decode_blocked_frame(Data),
    [Frame | decode_frames(RemainingData, PacketNumberEncoding)];
decode_frames(<<2#00000110:8, Data/binary>>, PacketNumberEncoding) ->
    % Stop waiting frame
    {RemainingData, Frame} = decode_stop_waiting_frame(Data, PacketNumberEncoding),
    [Frame | decode_frames(RemainingData, PacketNumberEncoding)];
decode_frames(<<2#00000111:8, Data/binary>>, PacketNumberEncoding) ->
    % Ping frame
    {RemainingData, Frame} = decode_ping_frame(Data),
    [Frame | decode_frames(RemainingData, PacketNumberEncoding)].

%% ------------------------------------------------------------------
%% Frame sequence encoding
%% ------------------------------------------------------------------

encode_frames(Frames, PacketNumberEncoding) ->
    [encode_frame(Frame, PacketNumberEncoding) || Frame <- Frames].

encode_frame(Frame, _PacketNumberEncoding) when is_record(Frame, stream_frame);
                                               is_record(Frame, stream_fin_frame) ->
    {Data, FinBit, DataLengthBit, OffsetHeaderEncoding, StreamIdEncoding} =
        quic_frame_stream:encode(Frame),
    [<<1:1,
       FinBit:1,
       DataLengthBit:1,
       OffsetHeaderEncoding:3,
       StreamIdEncoding:2>>,
     Data];
encode_frame(#ack_frame{} = Frame, _PacketNumberEncoding) ->
    {Data, MultipleAckRangesBit, LargestAckedEncoding, AckBlockEncoding} =
        quic_frame_ack:encode(Frame),
    [<<0:1,
       1:1,
       MultipleAckRangesBit:1,
       0:1, % unused
       LargestAckedEncoding:2,
       AckBlockEncoding:2>>,
     Data];
encode_frame(#padding_frame{} = Frame, _PacketNumberEncoding) ->
    [2#00000000, encode_padding_frame(Frame)];
encode_frame(#reset_stream_frame{} = Frame, _PacketNumberEncoding) ->
    [2#00000001, encode_reset_stream_frame(Frame)];
encode_frame(#connection_close_frame{} = Frame, _PacketNumberEncoding) ->
    [2#00000010, encode_connection_close_frame(Frame)];
encode_frame(#go_away_frame{} = Frame, _PacketNumberEncoding) ->
    [2#00000011, encode_go_away_frame(Frame)];
encode_frame(#window_update_frame{} = Frame, _PacketNumberEncoding) ->
    [2#00000100, encode_window_update_frame(Frame)];
encode_frame(#blocked_frame{} = Frame, _PacketNumberEncoding) ->
    [2#00000101, encode_blocked_frame(Frame)];
encode_frame(#stop_waiting_frame{} = Frame, PacketNumberEncoding) ->
    [2#00000110, encode_stop_waiting_frame(Frame, PacketNumberEncoding)];
encode_frame(#ping_frame{} = Frame, _PacketNumberEncoding) ->
    [2#00000111, encode_ping_frame(Frame)].

%% ------------------------------------------------------------------
%% Padding frame handling
%% ------------------------------------------------------------------

decode_padding_frame(PaddingData) ->
    {<<>>, #padding_frame{ size = byte_size(PaddingData) }}.

encode_padding_frame(#padding_frame{ size = Size }) ->
    [0 || _ <- lists:seq(1, Size)].

%% ------------------------------------------------------------------
%% Reset stream frame handling
%% ------------------------------------------------------------------

decode_reset_stream_frame(<<StreamId:4/little-unsigned-integer-unit:8,
                            ByteOffset:8/little-unsigned-integer-unit:8,
                            ErrorCode:4/binary,
                            RemainingData/binary>>) ->
    {RemainingData,
     #reset_stream_frame{ stream_id = StreamId,
                          byte_offset = ByteOffset,
                          error_code = ErrorCode }}.

encode_reset_stream_frame(#reset_stream_frame{ stream_id = StreamId,
                                               byte_offset = ByteOffset,
                                               error_code = ErrorCode }) ->
    <<StreamId:4/little-unsigned-integer-unit:8,
      ByteOffset:8/little-unsigned-integer-unit:8,
      ErrorCode:4/binary>>.

%% ------------------------------------------------------------------
%% Connection close frame handling
%% ------------------------------------------------------------------

decode_connection_close_frame(<<ErrorCode:4/binary,
                                ReasonPhraseLength:2/little-unsigned-integer-unit:8,
                                ReasonPhrase:ReasonPhraseLength/binary,
                                RemainingData/binary>>) ->
    {RemainingData,
     #connection_close_frame{ error_code = ErrorCode,
                              reason_phrase = ReasonPhrase }}.

encode_connection_close_frame(#connection_close_frame{ error_code = ErrorCode,
                                                       reason_phrase = ReasonPhrase }) ->
    ReasonPhraseLength = byte_size(ReasonPhrase),
    <<ErrorCode:4/binary,
      ReasonPhraseLength:2/little-unsigned-integer-unit:8,
      ReasonPhrase/binary>>.

%% ------------------------------------------------------------------
%% Go away frame handling
%% ------------------------------------------------------------------

decode_go_away_frame(<<ErrorCode:4/binary,
                       LastGoodStreamId:4/little-unsigned-integer-unit:8,
                       ReasonPhraseLength:2/little-unsigned-integer-unit:8,
                       ReasonPhrase:ReasonPhraseLength/binary,
                       RemainingData/binary>>) ->
    {RemainingData,
     #go_away_frame{ error_code = ErrorCode,
                     last_good_stream_id = LastGoodStreamId,
                     reason_phrase = ReasonPhrase }}.

encode_go_away_frame(#go_away_frame{ error_code = ErrorCode,
                                     last_good_stream_id = LastGoodStreamId,
                                     reason_phrase = ReasonPhrase }) ->
    ReasonPhraseLength = byte_size(ReasonPhrase),
    <<ErrorCode:4/binary,
      LastGoodStreamId:4/little-unsigned-integer-unit:8,
      ReasonPhraseLength:2/little-unsigned-integer-unit:8,
      ReasonPhrase/binary>>.

%% ------------------------------------------------------------------
%% Window update frame handling
%% ------------------------------------------------------------------

decode_window_update_frame(<<StreamId:4/little-unsigned-integer-unit:8,
                             ByteOffset:8/little-unsigned-integer-unit:8,
                             RemainingData/binary>>) ->
    {RemainingData,
     #window_update_frame{ stream_id = StreamId,
                           byte_offset = ByteOffset }}.

encode_window_update_frame(#window_update_frame{ stream_id = StreamId,
                                                 byte_offset = ByteOffset }) ->
    <<StreamId:4/little-unsigned-integer-unit:8,
      ByteOffset:8/little-unsigned-integer-unit:8>>.

%% ------------------------------------------------------------------
%% Blocked frame handling
%% ------------------------------------------------------------------

decode_blocked_frame(<<StreamId:4/little-unsigned-integer-unit:8,
                       RemainingData/binary>>) ->
    {RemainingData,
     #blocked_frame{ stream_id = StreamId }}.

encode_blocked_frame(#blocked_frame{ stream_id = StreamId }) ->
    <<StreamId:4/little-unsigned-integer-unit:8>>.

%% ------------------------------------------------------------------
%% Stop waiting frame handling
%% ------------------------------------------------------------------

decode_stop_waiting_frame(Data, PacketNumberEncoding) ->
    {RemainingData, LeastUnackedDelta} = quic_proto_varint:decode_u48(Data, PacketNumberEncoding),
    {RemainingData,
     #stop_waiting_frame{ least_unacked_delta = LeastUnackedDelta }}.

encode_stop_waiting_frame(#stop_waiting_frame{ least_unacked_delta = LeastUnackedDelta },
                          PacketNumberEncoding) ->
    quic_proto_varint:encode_u48(LeastUnackedDelta, PacketNumberEncoding).

%% ------------------------------------------------------------------
%% Ping frame handling
%% ------------------------------------------------------------------

decode_ping_frame(Data) ->
    {Data, #ping_frame{}}.

encode_ping_frame(#ping_frame{}) ->
    "".
