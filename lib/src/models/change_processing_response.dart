class ChangeProcessingResponse {
  final String status;
  final bool processed;
  final String message;

  ChangeProcessingResponse({
    required this.status,
    required this.processed,
    required this.message,
  });

  factory ChangeProcessingResponse.fromJson(Map<String, dynamic> json) {
    return ChangeProcessingResponse(
      status: json['status'] as String,
      processed: json['processed'] as bool,
      message: json['message'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status,
        'processed': processed,
        'message': message,
      };
}
