function CreateMessageSenders($amountSenders, $queueName) {
	for ($i=1; $i -le $amountSenders; $i++) {
		$sender = New-SBMessageReceiver -QueueName $queueName -ReceiveMode 'ReceiveAndDelete';
	}
}