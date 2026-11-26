import 'package:anywork_client/models.dart';

import '../../rust/api/studio/types/thread_stream.dart';

UserQuestionView userQuestionFromFrb(BridgeUserQuestion question) =>
    UserQuestionView(
      id: question.id,
      header: question.header,
      question: question.question,
      isOther: question.isOther,
      isSecret: question.isSecret,
      options: [
        for (final option in question.options ?? const [])
          UserQuestionOptionView(
            label: option.label,
            description: option.description,
          ),
      ],
    );
